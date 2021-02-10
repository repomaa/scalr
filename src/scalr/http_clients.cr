require "http/client"

module Scalr::HTTPClients
  @@clients = {} of String => HTTP::Client
  @@mutex = Mutex.new

  def self.client_for(host : String, tls = false, reconnect = false)
    @@mutex.synchronize do
      if reconnect
        @@clients[host] = HTTP::Client.new(host, tls: tls)
      else
        @@clients[host] ||= HTTP::Client.new(host, tls: tls)
      end
    end
  end
end
