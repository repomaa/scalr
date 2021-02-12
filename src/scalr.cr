require "./scalr/handlers/*"

module Scalr
  VERSION = "0.1.0"

  server = HTTP::Server.new([
    LogHandler.new,
    ErrorHandler.new,
    Server.new,
  ])

  server.listen(ACF.config.server.port)
end
