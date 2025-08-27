class JobEventsService
  class << self
    def clients
      @clients ||= []
    end
    
    def add_client(ws)
      clients << ws
    end
    
    def remove_client(ws)
      clients.delete(ws)
    end
    
    def broadcast_job_event(job_id, new_status)
      message = {
        jobId: job_id,
        newStatus: new_status
      }.to_json
      
      clients.each do |client|
        begin
          client.send(message)
        rescue => e
          Rails.logger.error "Failed to send job event: #{e.message}"
          remove_client(client)
        end
      end
    end
  end
end