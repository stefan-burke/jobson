require 'faye/websocket'

class JobEventsWebsocket
  KEEPALIVE_TIME = 15 # seconds

  def initialize(app)
    @app = app
  end

  def call(env)
    if Faye::WebSocket.websocket?(env) && env['PATH_INFO'] == '/api/v1/jobs/events'
      ws = Faye::WebSocket.new(env, nil, ping: KEEPALIVE_TIME)
      
      # Store WebSocket connection for broadcasting
      @clients ||= []
      @clients << ws

      ws.on :open do |event|
        Rails.logger.info "WebSocket connection opened for job events"
      end

      ws.on :message do |event|
        # Client shouldn't send messages, but handle if they do
        Rails.logger.debug "Received message: #{event.data}"
      end

      ws.on :close do |event|
        Rails.logger.info "WebSocket connection closed"
        @clients.delete(ws)
        ws = nil
      end

      # Return async Rack response
      ws.rack_response
    else
      @app.call(env)
    end
  end
  
  # Method to broadcast job events to all connected clients
  def self.broadcast_job_event(job_id, new_status)
    message = { jobId: job_id, newStatus: new_status }.to_json
    @clients&.each do |client|
      client.send(message)
    end
  end
end