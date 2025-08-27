# Base channel for job output streams (stdout/stderr)
class JobOutputChannel < ApplicationCable::Channel
  def subscribed
    return unless params[:job_id]
    stream_from "job_#{params[:job_id]}_#{output_type}"
  end

  private

  def output_type
    raise NotImplementedError, "Subclasses must define output_type"
  end
end