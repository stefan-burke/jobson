class Job
  include ActiveModel::Model
  include ActiveModel::Serialization

  attr_accessor :id, :name, :owner, :timestamps, :spec, :inputs

  STATUSES = %w[SUBMITTED RUNNING FINISHED ABORTED FATAL_ERROR].freeze

  def self.generate_job_id
    # Generate a 10-character base36 string like the Java version
    # SecureRandom.base36 generates lowercase alphanumeric strings
    SecureRandom.base36(8)  # 8 bytes = ~10-11 base36 chars
  end

  def self.all(page = 1, page_size = 50)  # Default 50 to match Java's Constants.DEFAULT_PAGE_SIZE
    # Get all job directories
    job_dirs = Dir.glob(FileStorageService.job_path('*'))
    
    # Load all jobs with their timestamps for sorting
    all_jobs = job_dirs.map do |job_dir|
      job_id = File.basename(job_dir)
      find(job_id)
    end.compact
    
    # Sort by last timestamp descending (newest first) to match Java's byFirstStatusDate
    # Java sorts by comparing b.lastTimestamp to a.lastTimestamp (reverse order)
    sorted_jobs = all_jobs.sort do |a, b|
      a_time = a.timestamps.last ? Time.parse(a.timestamps.last['time']) : Time.at(0)
      b_time = b.timestamps.last ? Time.parse(b.timestamps.last['time']) : Time.at(0)
      b_time <=> a_time  # Descending order (newest first)
    end
    
    # Apply pagination
    total = sorted_jobs.count
    start_idx = (page - 1) * page_size
    end_idx = start_idx + page_size
    paginated_jobs = sorted_jobs[start_idx...end_idx] || []

    { jobs: paginated_jobs, total: total, page: page, page_size: page_size }
  end

  def self.find(job_id)
    job_path = FileStorageService.job_path(job_id)
    return nil unless File.exist?(job_path)
    
    request_file = job_path.join('request.json')
    return nil unless File.exist?(request_file)
    
    request_data = JSON.parse(File.read(request_file))
    
    # Read spec from spec.json (Java format)
    spec_file = job_path.join('spec.json')
    spec_data = File.exist?(spec_file) ? JSON.parse(File.read(spec_file)) : {}
    spec_id = spec_data['id']
    
    # Read inputs from inputs.json (Java format)
    inputs_file = job_path.join('inputs.json')
    inputs_data = File.exist?(inputs_file) ? JSON.parse(File.read(inputs_file)) : {}
    
    new(
      id: job_id,
      name: request_data['name'],
      owner: request_data['owner'] || 'guest',
      timestamps: request_data['timestamps'] || [],
      spec: spec_id,
      inputs: inputs_data
    )
  end

  def self.create(params)
    job_id = generate_job_id
    job_path = FileStorageService.job_path(job_id)
    FileUtils.mkdir_p(job_path)
    
    # Convert inputs to hash (params[:inputs] is ActionController::Parameters)
    inputs_hash = params[:inputs]&.to_h || {}
    
    # Save request data in Java-compatible format
    # Java stores only id, name, owner, and timestamps in request.json
    request_data = {
      'id' => job_id,
      'name' => params[:name],
      'owner' => params[:owner] || 'guest',
      'timestamps' => []  # Will be updated when job runs
    }
    
    FileStorageService.write_json(job_path.join('request.json'), request_data)
    
    # Save initial timestamp
    add_timestamp(job_id, 'SUBMITTED', 'Job persisted')
    
    # Copy spec snapshot
    spec = JobSpec.find(params[:spec])
    if spec
      FileStorageService.write_json(job_path.join('spec.json'), spec.attributes)
    end
    
    # Save inputs
    FileStorageService.write_json(job_path.join('inputs.json'), inputs_hash)
    
    # Queue for execution
    JobExecutorJob.perform_later(job_id)
    
    find(job_id)
  end

  def self.load_timestamps(job_id)
    # Java stores timestamps in request.json, not a separate file
    request_file = FileStorageService.job_path(job_id).join('request.json')
    return [] unless File.exist?(request_file)
    request_data = JSON.parse(File.read(request_file))
    request_data['timestamps'] || []
  end

  def self.add_timestamp(job_id, status, message = nil)
    # Load the request.json file
    request_file = FileStorageService.job_path(job_id).join('request.json')
    request_data = JSON.parse(File.read(request_file))
    
    # Add the new timestamp (Java format with message)
    request_data['timestamps'] ||= []
    # Convert status to Java format (lowercase with hyphens instead of underscores)
    java_status = status.downcase.gsub('_', '-')
    timestamp_entry = {
      'status' => java_status,
      'time' => Time.now.utc.strftime('%Y-%m-%d %H:%M:%S.%LZ'),  # Java format
    }
    timestamp_entry['message'] = message if message
    request_data['timestamps'] << timestamp_entry
    
    # Write back to request.json
    FileStorageService.write_json(request_file, request_data)
  end

  def latest_status
    return nil if timestamps.empty?
    timestamps.last['status']
  end

  def abort
    return false unless %w[SUBMITTED RUNNING].include?(latest_status)
    
    self.class.add_timestamp(id, 'ABORTED')
    
    # Kill the process if running
    pid_file = FileStorageService.job_path(id).join('pid')
    if File.exist?(pid_file)
      pid = File.read(pid_file).to_i
      begin
        Process.kill('TERM', pid)
      rescue Errno::ESRCH
        # Process already dead
      end
      File.delete(pid_file)
    end
    
    true
  end

  def stdout
    stdout_file = FileStorageService.job_path(id).join('stdout')
    return '' unless File.exist?(stdout_file)
    File.read(stdout_file)
  end
  
  def stdout_exists?
    # Java only includes stdout link if file exists and is non-empty
    stdout_file = FileStorageService.job_path(id).join('stdout')
    File.exist?(stdout_file) && File.size(stdout_file) > 0
  end

  def stderr
    stderr_file = FileStorageService.job_path(id).join('stderr')
    return '' unless File.exist?(stderr_file)
    File.read(stderr_file)
  end
  
  def stderr_exists?
    # Java only includes stderr link if file exists and is non-empty
    stderr_file = FileStorageService.job_path(id).join('stderr')
    File.exist?(stderr_file) && File.size(stderr_file) > 0
  end

  def outputs
    outputs_dir = FileStorageService.job_path(id).join('outputs')
    return [] unless File.exist?(outputs_dir)
    
    Dir.glob(File.join(outputs_dir, '*')).map do |file|
      {
        'id' => File.basename(file),
        'name' => File.basename(file),
        'size' => File.size(file),
        'mimeType' => `file -b --mime-type #{file}`.strip
      }
    end
  end

  def output_path(output_id)
    FileStorageService.job_path(id).join('outputs', output_id)
  end

  def attributes
    {
      'id' => id,
      'name' => name,
      'owner' => owner,
      'timestamps' => timestamps
    }
  end
end