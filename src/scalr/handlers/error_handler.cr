require "athena"
require "http/server/handler"

module Scalr
  class ErrorHandler
    include HTTP::Handler

    INTERNAL_SERVER_ERROR = {
      status: 500,
      message: "Something went wrong"
    }

    def initialize
      @serializer = ASR::Serializer.new
    end

    def call(context : HTTP::Server::Context)
      response = context.response

      begin
        call_next(context)
      rescue ex
        if ex.is_a?(ART::Exceptions::HTTPException)
          response.status = ex.status
          @serializer.serialize(ex, :json, response)
        else
          response.status = HTTP::Status::INTERNAL_SERVER_ERROR
          @serializer.serialize(INTERNAL_SERVER_ERROR, :json, response)
        end

        Log.error do
          ex.inspect_with_backtrace
        end
      end
    end
  end
end
