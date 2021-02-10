require "uri"
require "athena"

module Scalr::ParamConverters
  @[ADI::Register]
  struct URL < ART::ParamConverterInterface
    def apply(request : HTTP::Request, configuration : Configuration) : Nil
      arg_name = configuration.name
      return unless request.attributes.has? arg_name
      string_value = request.attributes.get(arg_name, String)
      request.attributes.set(arg_name, URI.parse(string_value))
    end
  end
end
