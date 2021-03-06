module Rack::Reqorder::Models
  class HttpResponse
    include ::Mongoid::Document
    include ::Mongoid::Timestamps

    field :headers, type: Hash
    field :status, type: Integer
    field :body, type: String
    field :length, type: Integer
    field :response_time, type: Float

    belongs_to :http_request, {dependent: :nullify}.merge(REQUIRED)
    belongs_to :recording, {dependent: :nullify}.merge(REQUIRED)

    before_create :set_response_time
    after_create :set_response_time_to_request

  private
    def set_response_time
      self.response_time = self.created_at - self.http_request.created_at
    end

    def set_response_time_to_request
      self.http_request.response_time = self.response_time
      self.http_request.save!
    end
  end
end
