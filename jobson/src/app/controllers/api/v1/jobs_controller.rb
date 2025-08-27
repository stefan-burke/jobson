module Api
  module V1
    class JobsController < ApplicationController
      def index
        page = params[:page]&.to_i || 1
        page_size = params[:page_size]&.to_i || 20
        
        result = Job.all(page, page_size)
        
        render json: {
          entries: result[:jobs].map { |job| job_details(job) },
          page: result[:page],
          pageSize: result[:page_size],
          total: result[:total],
          _links: pagination_links(page, page_size, result[:total])
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
        job_request = params.permit(:name, :spec, inputs: {})
        
        # Validate spec exists
        spec = JobSpec.find(job_request[:spec])
        unless spec
          render json: { error: 'Invalid job spec' }, status: :bad_request
          return
        end
        
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
            outputs: job.outputs.map { |output| output_details(job.id, output) }
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

      private

      def job_details(job)
        {
          'id' => job.id,
          'name' => job.name,
          'owner' => job.owner,
          'timestamps' => job.timestamps,
          '_links' => {
            'self' => { 'href' => "/v1/jobs/#{job.id}" },
            'abort' => { 'href' => "/v1/jobs/#{job.id}/abort" },
            'stdout' => { 'href' => "/v1/jobs/#{job.id}/stdout" },
            'stderr' => { 'href' => "/v1/jobs/#{job.id}/stderr" },
            'spec' => { 'href' => "/v1/jobs/#{job.id}/spec" },
            'inputs' => { 'href' => "/v1/jobs/#{job.id}/inputs" },
            'outputs' => { 'href' => "/v1/jobs/#{job.id}/outputs" }
          }
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