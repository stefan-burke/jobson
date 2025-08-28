module Api
  module V1
    class JobSpecsController < ApplicationController
      def index
        Rails.logger.info "JobSpecsController#index called!"
        specs = JobSpec.all
        Rails.logger.info "Returning #{specs.count} specs"
        render json: {
          entries: specs.map { |spec| spec_summary(spec) },
          _links: {}  # Java API includes empty _links
        }
      end

      def show
        spec = JobSpec.find(params[:id])
        if spec
          render json: spec.attributes
        else
          render json: { error: 'Job spec not found' }, status: :not_found
        end
      end

      private

      def spec_summary(spec)
        {
          'id' => spec.id,
          'name' => spec.name,
          'description' => spec.description,
          '_links' => {
            'details' => {
              'href' => "/v1/specs/#{spec.id}"
            }
          }
        }
      end
    end
  end
end