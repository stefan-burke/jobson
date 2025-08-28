class RootController < ApplicationController
  def index
    render json: {
      '_links' => {
        'v1' => { 'href' => '/v1/' }
      }
    }
  end
end