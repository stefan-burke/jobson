module Api
  module V1
    class RootController < ApplicationController
      def index
        render json: {
          '_links' => {
            'specs' => { 'href' => '/v1/specs' },
            'jobs' => { 'href' => '/v1/jobs' }
          }
        }
      end
    end
  end
end