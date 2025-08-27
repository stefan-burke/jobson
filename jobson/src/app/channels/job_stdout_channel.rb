class JobStdoutChannel < ApplicationCable::Channel
  def subscribed
    job_id = params[:job_id]
    stream_from "job_#{job_id}_stdout" if job_id
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end