require "uri"
require "athena"
require "./base"

module Scalr::ParamConverters
  struct URL
    include Base(URI)

    protected def convert(request : HTTP::Request) : URI
      string_value = request.query_params[name]
      return URI.parse(string_value)
    end
  end
end
