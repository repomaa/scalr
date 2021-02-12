require "athena"
require "../services/image_processor"
require "./base"

module Scalr::ParamConverters
  struct ImageProcessorOptions
    include Base(Services::ImageProcessor::Options)

    protected def convert(request : HTTP::Request) : Services::ImageProcessor::Options
      width = request.query_params["width"]?.try(&.to_i)
      height = request.query_params["height"]?.try(&.to_i)
      scale = request.query_params["scale"]?.try(&.to_i)

      fit = request.query_params["fit"]?.try do |string|
        Services::ImageProcessor::Options::Fit.parse(string)
      end

      gravity = request.query_params["gravity"]?.try do |string|
        Services::ImageProcessor::Options::Gravity.parse(string)
      end

      format = request.query_params["format"]?

      options = Services::ImageProcessor::Options.new(
        width: width,
        height: height,
        scale: scale,
        format: format,
        fit: fit,
        gravity: gravity,
      )

      violations = AVD.validator.validate(options)
      raise AVD::Exceptions::ValidationFailed.new(violations) if violations.any?

      return options
    end
  end
end
