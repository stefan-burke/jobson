module Api
  module V1
    class JobSpecsController < ApplicationController
      def index
        specs = JobSpec.all
        render json: {
          specs: specs.map { |spec| spec_summary(spec) }
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
            'self' => { 'href' => "/v1/specs/#{spec.id}" }
          }
        }
      end
    end
  end
end