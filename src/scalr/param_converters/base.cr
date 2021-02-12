require "athena"

module Scalr::ParamConverters
  module Base(T)
    protected getter name : String

    def initialize(@name)
    end

    def run(request : HTTP::Request) : T
      convert(request)
    rescue ex
      raise ART::Exceptions::BadRequest.new("failed to parse #{name}: #{ex}")
    end

    protected abstract def convert(request : HTTP::Request) : T
  end
end
