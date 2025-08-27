class Api::V1::UsersController < ApplicationController
  def current
    render json: {
      id: "guest"
    }
  end
end