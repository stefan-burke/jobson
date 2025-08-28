class FileStorageService
  class << self
    def workspace_path
      @workspace_path ||= Rails.root.join('workspace')
    end

    def ensure_directories
      # Create Rails workspace directories
      %w[specs users].each do |dir|
        FileUtils.mkdir_p(workspace_path.join(dir))
      end
      # Ensure shared Java directories exist
      FileUtils.mkdir_p('/tmp/jobson-jobs')
      FileUtils.mkdir_p('/tmp/jobson-wds')
    end

    def job_path(job_id)
      # Use the same job directory as Java for compatibility testing
      Pathname.new('/tmp/jobson-jobs').join(job_id)
    end

    def spec_path(spec_id)
      workspace_path.join('specs', spec_id)
    end

    def working_dir_path(job_id)
      # Use the same working directory as Java for compatibility testing
      Pathname.new('/tmp/jobson-wds').join(job_id)
    end

    def read_json(path)
      return nil unless File.exist?(path)
      JSON.parse(File.read(path))
    end

    def write_json(path, data)
      FileUtils.mkdir_p(File.dirname(path))
      # Convert Rails objects to plain Ruby objects for JSON serialization
      json_data = case data
                  when Hash, ActionController::Parameters
                    data.to_h
                  when Array
                    data.map { |item| item.respond_to?(:to_h) ? item.to_h : item }
                  else
                    data
                  end
      File.write(path, JSON.pretty_generate(json_data))
    end
  end
end