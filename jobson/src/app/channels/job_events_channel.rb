class JobEventsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "job_events"
  end

  def unsubscribed
    # Any cleanup needed when channel is unsubscribed
  end
end