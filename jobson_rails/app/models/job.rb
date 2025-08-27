class Job
  include ActiveModel::Model
  include ActiveModel::Serialization

  attr_accessor :id, :name, :owner, :timestamps, :spec, :inputs

  STATUSES = %w[SUBMITTED RUNNING FINISHED ABORTED FATAL_ERROR].freeze

  def self.all(page = 1, page_size = 20)
    job_dirs = Dir.glob(FileStorageService.job_path('*')).sort.reverse
    total = job_dirs.count
    
    start_idx = (page - 1) * page_size
    end_idx = start_idx + page_size
    
    jobs = job_dirs[start_idx...end_idx].map do |job_dir|
      job_id = File.basename(job_dir)
      find(job_id)
    end.compact

    { jobs: jobs, total: total, page: page, page_size: page_size }
  end

  def self.find(job_id)
    job_path = FileStorageService.job_path(job_id)
    return nil unless File.exist?(job_path)
    
    request_file = job_path.join('request.json')
    return nil unless File.exist?(request_file)
    
    request_data = JSON.parse(File.read(request_file))
    
    new(
      id: job_id,
      name: request_data['name'],
      owner: request_data['owner'] || 'anonymous',
      timestamps: load_timestamps(job_id),
      spec: request_data['spec'],
      inputs: request_data['inputs']
    )
  end

  def self.create(params)
    job_id = SecureRandom.uuid
    job_path = FileStorageService.job_path(job_id)
    FileUtils.mkdir_p(job_path)
    
    # Save request data
    request_data = {
      'id' => job_id,
      'name' => params[:name],
      'spec' => params[:spec],
      'inputs' => params[:inputs],
      'owner' => params[:owner] || 'anonymous'
    }
    
    FileStorageService.write_json(job_path.join('request.json'), request_data)
    
    # Save initial timestamp
    add_timestamp(job_id, 'SUBMITTED')
    
    # Copy spec snapshot
    spec = JobSpec.find(params[:spec])
    if spec
      FileStorageService.write_json(job_path.join('spec.json'), spec.attributes)
    end
    
    # Save inputs
    FileStorageService.write_json(job_path.join('inputs.json'), params[:inputs] || {})
    
    # Queue for execution
    JobExecutorJob.perform_later(job_id)
    
    find(job_id)
  end

  def self.load_timestamps(job_id)
    timestamp_file = FileStorageService.job_path(job_id).join('timestamps.json')
    return [] unless File.exist?(timestamp_file)
    JSON.parse(File.read(timestamp_file))
  end

  def self.add_timestamp(job_id, status)
    timestamps = load_timestamps(job_id)
    timestamps << {
      'status' => status,
      'time' => Time.now.iso8601
    }
    FileStorageService.write_json(
      FileStorageService.job_path(job_id).join('timestamps.json'),
      timestamps
    )
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

  def stderr
    stderr_file = FileStorageService.job_path(id).join('stderr')
    return '' unless File.exist?(stderr_file)
    File.read(stderr_file)
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