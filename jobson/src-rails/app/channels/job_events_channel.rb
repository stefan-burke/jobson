class JobEventsChannel < ApplicationCable::Channel
  def subscribed
    stream_from "job_events"
  end
end