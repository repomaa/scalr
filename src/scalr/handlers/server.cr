require "http/server/handler"
require "../services/image_processor"
require "../services/s3"
require "../param_converters/url"
require "../param_converters/image_processor_options"
require "../config"
require "../http_clients"

module Scalr
  class Server
    include HTTP::Handler

    TIME_FORMAT = "%a, %d %b %Y %H:%M:%S %Z"

    private getter allowed_hosts : Array(Regex)

    def initialize
      @http_clients = HTTPClients.new
      @allowed_hosts = ACF.config.server.allowed_hosts
      @image_processor = Scalr::Services::ImageProcessor.new
      @s3 = Scalr::Services::S3.new(ACF.config.s3)
      @serializer = ASR::Serializer.new
      @url_converter = ParamConverters::URL.new("url")
      @options_converter = ParamConverters::ImageProcessorOptions.new("options")
    end

    def call(context : HTTP::Server::Context)
      request = context.request
      return call_next(context) if request.method != "GET"
      return call_next(context) if request.path != "/images"

      url = @url_converter.run(request)
      options = @options_converter.run(request)

      original = @s3.get_original(hash_original(url))
      conversion = @s3.get_conversion(hash_conversion(url, options))
      fetch_if_needed(original, url)
      convert_if_needed(original, conversion, options)

      expires = original.headers["x-amz-meta-original-expires"]?.try do |value|
        Time.unix(value.to_i)
      end

      redirect_to(context.response, conversion.presigned_url)
    end

    private def redirect_to(response, url)
      response.status = HTTP::Status::FOUND
      expires = 1.week.from_now.at_beginning_of_week
      max_age = (expires - Time.utc).total_seconds.to_i
      response.headers["Cache-Control"] = "public, max-age=#{max_age}"
      response.headers["Location"] = url
    end

    private def convert_if_needed(original, conversion, options)
      if conversion.exists? && !original.modified?
        Log.info { "Conversion exists" }
        return
      end

      Log.info { "Converting..." }

      conversion_content_type = options.format.try do |f|
        MIME.from_extension(".#{f}")
      end

      conversion_content_type ||= original.headers["Content-Type"]

      conversion.write do |io, headers|
        io.write(@image_processor.process(original.blob, options))
        headers["Content-Type"] = conversion_content_type
      end
    end

    private def fetch_if_needed(original, url)
      host = url.host
      original.headers["x-amz-meta-original-expires"]?.try do |expires|
        if Time.unix(expires.to_i) > Time.utc
          Log.info { "Cache for original still valid" }
          return
        end
      end

      if host.nil?
        raise ART::Exceptions::BadRequest.new("invalid url #{url}")
      end

      if allowed_hosts.none?(&.matches?(host))
        raise ART::Exceptions::Forbidden.new("host #{host} not in whitelist")
      end

      @http_clients.with_client_for(host, tls: url.scheme == "https") do |client|
        try_fetch(original, client, url)
      end
    end

    private def try_fetch(original, client, url)
      request_headers = HTTP::Headers.new

      original.headers["x-amz-meta-original-etag"]?.try do |value|
        request_headers["If-None-Match"] = value
      end

      original.headers["x-amz-meta-original-last-modified"]?.try do |value|
        request_headers["If-Modified-Since"] = value
      end

      client.get(url.to_s, headers: request_headers) do |response|
        if response.status.not_modified?
          Log.info { "Original is unmodified" }
          expires = extract_expires(response.headers)
          if expires > Time.utc
            Log.info { "Updating headers" }
            original.headers["x-amz-meta-original-expires"] = expires.to_unix.to_s
            original.update_headers
          end

          next
        end

        unless response.success?
          raise "server responded with #{response.status}"
        end

        content_type = response.content_type
        raise "Missing Content-Type header" if content_type.nil?

        Log.info { "Updating original" }

        original.write do |io, headers|
          IO.copy(response.body_io, io)
          etag = response.headers["ETag"]?
          last_modified = response.headers["Last-Modified"]?

          expires = extract_expires(response.headers)
          headers["x-amz-meta-original-expires"] = expires.to_unix.to_s
          headers["Content-Type"] = content_type

          etag.try { |value| headers["x-amz-meta-original-etag"] = value }
          last_modified.try { |value| headers["x-amz-meta-original-last-modified"] = value }
        end
      rescue ex
        ex.inspect_with_backtrace(STDERR)
        raise ART::Exceptions::BadRequest.new(
          "Failed to fetch image from url: #{ex}"
        )
      end
    end

    private def hash_original(url)
      Digest::MD5.hexdigest(url.to_s)
    end

    private def hash_conversion(url, options)
      digest = Digest::MD5.new
      digest.update(url.to_s)
      digest.update(@serializer.serialize(options, :json))
      digest.final.hexstring
    end

    private def extract_expires(headers)
      cache_control = headers["Cache-Control"]?
      expires = headers["Expires"]?

      unless cache_control.nil?
        return Time.utc unless headers.includes_word?("Cache-Control", "public")

        directives = cache_control
          .split(/,\s*/)
          .select(&.includes?('='))
          .reduce(Hash(String, String).new) do |acc, directive|
            key, value = directive.split('=')
            acc.merge({ key => value })
          end

        directives["s-maxage"]?.try do |seconds|
          return Time.utc + seconds.to_i.seconds
        end

        directives["max-age"]?.try do |seconds|
          return Time.utc + seconds.to_i.seconds
        end
      end

      return Time.utc if expires.nil?
      Time.parse!(expires, TIME_FORMAT)
    end
  end
end
