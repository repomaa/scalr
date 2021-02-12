require "http/server/handler"

module Scalr
  class LogHandler
    include HTTP::Handler

    def call(context)
      started = Time.utc
      call_next(context)
      req = context.request
      res = context.response
      span = Time.utc - started
      duration = format(span)

      Log.info do
        "#{req.method} #{req.resource} -> #{res.status_code} [#{duration}]"
      end
    end

    private def format(span)
      case
      when span.total_seconds > 1 then "%.2fs" % span.total_seconds
      when span.total_milliseconds > 1 then "%.2fms" % span.total_milliseconds
      when span.total_microseconds > 1 then "%.2fµs" % span.total_microseconds
      when span.total_nanoseconds > 1 then "%.2fns" % span.total_nanoseconds
      end
    end
  end
end
