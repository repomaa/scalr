require "./scalr/handlers/*"

module Scalr
  VERSION = "0.1.0"

  server = HTTP::Server.new([
    LogHandler.new,
    ErrorHandler.new,
    Server.new,
  ])

  server.listen("0.0.0.0", ACF.config.server.port)
end
