class JobExecutorJob < ApplicationJob
  queue_as :default

  def perform(job_id)
    job = Job.find(job_id)
    return unless job
    
    Job.add_timestamp(job_id, 'RUNNING', 'Submitted to executor')
    
    # Broadcast status update
    ActionCable.server.broadcast("job_events", {
      job_id: job_id,
      status: 'RUNNING',
      timestamp: Time.now.iso8601
    })
    
    begin
      execute_job(job)
      Job.add_timestamp(job_id, 'FINISHED', 'Execution finished')
      
      ActionCable.server.broadcast("job_events", {
        job_id: job_id,
        status: 'FINISHED',
        timestamp: Time.now.iso8601
      })
    rescue => e
      Rails.logger.error "Job #{job_id} failed: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      
      Job.add_timestamp(job_id, 'FATAL_ERROR', e.message)
      
      # Write error to stderr
      stderr_file = FileStorageService.job_path(job_id).join('stderr')
      File.open(stderr_file, 'a') do |f|
        f.puts "Error: #{e.message}"
        f.puts e.backtrace.join("\n")
      end
      
      ActionCable.server.broadcast("job_events", {
        job_id: job_id,
        status: 'FATAL_ERROR',
        timestamp: Time.now.iso8601
      })
    end
  end

  private

  def execute_job(job)
    spec = JobSpec.find(job.spec)
    return unless spec
    
    # Create working directory
    working_dir = FileStorageService.working_dir_path(job.id)
    FileUtils.mkdir_p(working_dir)
    
    # Prepare command from template
    command = prepare_command(spec.execution, job.inputs)
    Rails.logger.info "Executing command: #{command}"
    Rails.logger.info "With inputs: #{job.inputs.inspect}"
    
    # Execute command
    stdout_file = FileStorageService.job_path(job.id).join('stdout')
    stderr_file = FileStorageService.job_path(job.id).join('stderr')
    pid_file = FileStorageService.job_path(job.id).join('pid')
    
    FileUtils.touch(stdout_file)
    FileUtils.touch(stderr_file)
    
    # Run the command
    Dir.chdir(working_dir) do
      IO.popen(command, err: [:child, :out]) do |io|
        File.write(pid_file, io.pid)
        
        io.each_line do |line|
          File.open(stdout_file, 'a') { |f| f.puts line }
          
          # Broadcast stdout updates
          ActionCable.server.broadcast("job_#{job.id}_stdout", {
            data: line,
            timestamp: Time.now.iso8601
          })
        end
      end
    end
    
    # Clean up pid file
    File.delete(pid_file) if File.exist?(pid_file)
    
    # Copy outputs
    copy_outputs(job.id, working_dir, spec.expected_outputs)
  end

  def prepare_command(execution_config, inputs)
    return '' unless execution_config
    
    application = execution_config['application']
    arguments = execution_config['arguments'] || []
    
    # Build command with templated arguments
    templated_args = arguments.map do |arg|
      template_value(arg, inputs)
    end
    
    [application, *templated_args].join(' ')
  end

  def template_value(template, inputs)
    return template unless template.is_a?(String)
    
    # Simple template replacement for ${inputs.fieldName}
    result = template.gsub(/\$\{inputs\.(\w+)\}/) do |match|
      field_name = $1
      value = inputs[field_name]
      
      if value.nil?
        raise "Missing input '#{field_name}' in job inputs"
      end
      
      value.to_s
    end
    
    result
  end

  def copy_outputs(job_id, working_dir, expected_outputs)
    return unless expected_outputs
    
    outputs_dir = FileStorageService.job_path(job_id).join('outputs')
    FileUtils.mkdir_p(outputs_dir)
    
    expected_outputs.each do |output_config|
      output_id = output_config['id']
      path = output_config['path']
      
      next unless path
      
      source = File.join(working_dir, path)
      if File.exist?(source)
        destination = outputs_dir.join(output_id)
        FileUtils.cp_r(source, destination)
      end
    end
  end
end