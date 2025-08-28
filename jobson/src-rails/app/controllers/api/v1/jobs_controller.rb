module Api
  module V1
    class JobsController < ApplicationController
      def index
        Rails.logger.info "JobsController#index called! Path: #{request.path}"
        
        # Java defaults to page_size of 50 (see Constants.DEFAULT_PAGE_SIZE)
        # TypeScript sends 0-based page numbers, but our model uses 1-based
        page = (params[:page]&.to_i || 0) + 1
        page_size = params[:page_size]&.to_i || 50  # Changed from 20 to 50 to match Java
        
        result = Job.all(page, page_size)
        
        # Debug: Log what we're about to return
        Rails.logger.info "Jobs index returning: page=#{result[:page]}, total=#{result[:total]}"
        
        # Java API only returns entries and _links, no pagination fields
        render json: {
          entries: result[:jobs].map { |job| job_details(job) },
          _links: {}  # Java returns empty links for the collection
        }
      end

      def show
        job = Job.find(params[:id])
        if job
          render json: job_details(job)
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def create
        # Handle both nested and non-nested params
        if params[:job]
          job_request = params.require(:job).permit(:name, :spec, inputs: {})
        else
          job_request = params.permit(:name, :spec, inputs: {})
        end
        
        # Validate spec exists
        spec = JobSpec.find(job_request[:spec])
        unless spec
          render json: { error: 'Invalid job spec' }, status: :bad_request
          return
        end
        
        # Ensure owner is set to 'guest' for guest authentication (matching Java)
        job_request[:owner] = 'guest'
        job = Job.create(job_request)
        
        render json: {
          id: job.id,
          _links: {
            'self' => { 'href' => "/v1/jobs/#{job.id}" }
          }
        }, status: :created
      end

      def destroy
        job = Job.find(params[:id])
        if job
          # Just mark as deleted, don't actually remove files
          FileUtils.touch(FileStorageService.job_path(job.id).join('.deleted'))
          head :no_content
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def abort
        job = Job.find(params[:id])
        if job
          if job.abort
            head :no_content
          else
            render json: { error: 'Cannot abort job in current state' }, status: :bad_request
          end
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def stdout
        job = Job.find(params[:id])
        if job
          render plain: job.stdout
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def stderr
        job = Job.find(params[:id])
        if job
          render plain: job.stderr
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def spec
        job = Job.find(params[:id])
        if job
          spec = JobSpec.find(job.spec)
          if spec
            render json: spec.attributes
          else
            render json: { error: 'Job spec not found' }, status: :not_found
          end
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def inputs
        job = Job.find(params[:id])
        if job
          render json: job.inputs || {}
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def outputs
        job = Job.find(params[:id])
        if job
          render json: {
            entries: job.outputs.map { |output| output_details(job.id, output) }
          }
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end

      def output
        job = Job.find(params[:id])
        if job
          output_path = job.output_path(params[:output_id])
          if File.exist?(output_path)
            send_file output_path, disposition: 'attachment'
          else
            render json: { error: 'Output not found' }, status: :not_found
          end
        else
          render json: { error: 'Job not found' }, status: :not_found
        end
      end
      
      def events
        # Handle WebSocket upgrade for job events
        if Faye::WebSocket.websocket?(request.env)
          ws = Faye::WebSocket.new(request.env)
          
          ws.on :open do |event|
            Rails.logger.info "Job events WebSocket opened"
            # Store connection for broadcasting
            JobEventsService.add_client(ws)
          end
          
          ws.on :close do |event|
            Rails.logger.info "Job events WebSocket closed"
            JobEventsService.remove_client(ws)
            ws = nil
          end
          
          # Return async Rack response
          ws.rack_response
        else
          head :upgrade_required
        end
      end
      
      def stdout_updates
        handle_output_updates(:stdout)
      end
      
      def stderr_updates
        handle_output_updates(:stderr)
      end

      private
      
      def handle_output_updates(output_type)
        job_id = params[:id]
        
        if Faye::WebSocket.websocket?(request.env)
          ws = Faye::WebSocket.new(request.env)
          job = Job.find(job_id)
          
          if job.nil?
            ws.close
            return ws.rack_response
          end
          
          ws.on :open do |event|
            Rails.logger.info "#{output_type} updates WebSocket opened for job #{job_id}"
            
            # Send current output immediately as binary data (Blob)
            current_output = output_type == :stdout ? job.stdout : job.stderr
            if current_output && !current_output.empty?
              # Send as binary frame - this will be received as a Blob in the browser
              ws.send(current_output.force_encoding('BINARY'))
            end
            
            # TODO: Set up file watching or polling to send updates
            # For now, just keep the connection open
          end
          
          ws.on :close do |event|
            Rails.logger.info "#{output_type} updates WebSocket closed for job #{job_id}"
            ws = nil
          end
          
          ws.rack_response
        else
          head :upgrade_required
        end
      end

      def job_details(job)
        # Convert status values to lowercase for UI compatibility
        normalized_timestamps = job.timestamps.map do |ts|
          {
            'status' => ts['status'].downcase,
            'time' => ts['time']
          }
        end
        
        # Build base links (Java includes links conditionally based on what exists)
        links = {
          'self' => { 'href' => "/v1/jobs/#{job.id}" },
          'spec' => { 'href' => "/v1/jobs/#{job.id}/spec" },
          'outputs' => { 'href' => "/v1/jobs/#{job.id}/outputs" }
        }
        
        # Only include inputs link if job has inputs
        if job.inputs && !job.inputs.empty?
          links['inputs'] = { 'href' => "/v1/jobs/#{job.id}/inputs" }
        end
        
        # Only include stdout link if stdout file exists
        if job.stdout_exists?
          links['stdout'] = { 'href' => "/v1/jobs/#{job.id}/stdout" }
        end
        
        # Only include stderr link if stderr file exists
        if job.stderr_exists?
          links['stderr'] = { 'href' => "/v1/jobs/#{job.id}/stderr" }
        end
        
        # Only include abort link for running/submitted jobs
        if job.latest_status && %w[SUBMITTED RUNNING].include?(job.latest_status)
          links['abort'] = { 'href' => "/v1/jobs/#{job.id}/abort" }
        end
        
        {
          'id' => job.id,
          'name' => job.name,
          'owner' => job.owner,
          'timestamps' => normalized_timestamps,
          '_links' => links
        }
      end

      def output_details(job_id, output)
        output.merge(
          '_links' => {
            'self' => { 'href' => "/v1/jobs/#{job_id}/outputs/#{output['id']}" }
          }
        )
      end

      def pagination_links(page, page_size, total)
        total_pages = (total.to_f / page_size).ceil
        links = {}
        
        links['first'] = { 'href' => "/v1/jobs?page=1&page_size=#{page_size}" }
        links['last'] = { 'href' => "/v1/jobs?page=#{total_pages}&page_size=#{page_size}" }
        
        if page > 1
          links['prev'] = { 'href' => "/v1/jobs?page=#{page - 1}&page_size=#{page_size}" }
        end
        
        if page < total_pages
          links['next'] = { 'href' => "/v1/jobs?page=#{page + 1}&page_size=#{page_size}" }
        end
        
        links
      end
    end
  end
end