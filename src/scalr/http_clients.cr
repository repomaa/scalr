require "./config"
require "pool"
require "http/client"

module Scalr
  class HTTPClients
    def initialize
      @clients = Hash({String, Bool}, Pool(HTTP::Client)).new
      @mutex = Mutex.new
    end

    def with_client_for(host : String, tls = false, &block : HTTP::Client -> T) : T forall T
      pool = get_pool(host, tls)

      retries = 0

      loop do
        pool.get do |client|
          return yield client
        end
      rescue ex : IO::Error
        raise ex if retries > 2
        retries += 1
      end
    end

    private def get_pool(host, tls)
      @mutex.synchronize do
        @clients[{host, tls}] ||= Pool.new { HTTP::Client.new(host, tls: tls) }
      end
    end
  end
end
