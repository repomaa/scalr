require "athena"
require "awscr-s3"
require "../config"
require "../ext/awscr_client"

module Scalr::Services
  @[ADI::Register(public: true, name: "s3")]
  class S3
    DEFAULT_REGION = "us-east-1"
    DEFAULT_HOST = "s3.amazonaws.com"

    @config : Config::S3

    class Object
      getter? exists
      getter? modified
      getter headers

      def initialize(
        @client : Awscr::S3::Client,
        @config : Scalr::Config::S3,
        @bucket : String,
        @key : String,
      )
        @modified = false
        @exists = false
        @cache = IO::Memory.new
        @headers = HTTP::Headers.new

        begin
          @headers = @client.head_object(@bucket, @key).headers
          @exists = true
        rescue
        end
      end

      def presigned_url(**options)
        raise "Cannot generate presigned url for non-existing object" unless exists?

        object = "/#{@key}"

        request = build_request("GET", @bucket, object)
        options.each do |k, v|
          request.query_params.add(k.to_s, v)
        end

        presign_request(request)

        String.build do |str|
          str << (@config.public_endpoint.try(&.scheme) || "https") << "://"
          str << request.host_with_port
          str << request.resource
        end
      end

      def read(&block : (IO, HTTP::Headers) ->) : Void
        raise "Cannot read from non-existing object" unless exists?

        if @cache.empty?
          @client.get_object(@bucket, @key) do |response|
            IO.copy(response.body_io, @cache)
          end
        end

        @cache.rewind
        yield @cache, @headers
      end

      def blob : Bytes
        read {}
        @cache.to_slice
      end

      def write(&block : (IO, HTTP::Headers) ->) : Void
        @cache.clear
        @headers.clear

        yield @cache, @headers

        headers = Hash(String, String).new
        @headers.each do |key, values|
          headers[key] = values.first
        end

        @client.put_object(@bucket, @key, @cache.to_slice, headers: headers.to_h)
        @exists = true
        @modified = true
      end

      private def presign_request(request : HTTP::Request)
        @client.signer.presign(request)
      end

      private def build_request(method : String, bucket : String, object : String)
        headers = HTTP::Headers{"Host" => host}
        body = "UNSIGNED-PAYLOAD"

        request = HTTP::Request.new(
          method,
          "/#{bucket}#{object}",
          headers,
          body
        )

        request.query_params.add("X-Amz-Expires", "300")
        request
      end

      private def host
        if endpoint = @config.public_endpoint
          host_from_endpoint(endpoint)
        else
          return DEFAULT_HOST if @config.region == DEFAULT_REGION
          "s3-#{@config.region}.amazonaws.com"
        end
      end

      private def host_from_endpoint(endpoint : URI) : String
        host = endpoint.host
        raise "Missing host from endpoint uri" if host.nil?

        default_port?(endpoint) ? host : "#{host}:#{endpoint.port}"
      end

      private def default_port?(endpoint)
        endpoint.scheme == "http" && endpoint.port == 80 ||
        endpoint.scheme == "https" && endpoint.port == 443
      end
    end

    def initialize(
      @request_store : ART::RequestStore,
    )
      @config = ACF.config.s3
      @client = Awscr::S3::Client.new(
        region: @config.region,
        aws_access_key: @config.key,
        aws_secret_key: @config.secret,
        endpoint: @config.endpoint.to_s,
      )
    end

    def get_original(object)
      bucket = @config.buckets.originals
      Object.new(@client, @config, bucket, object)
    end

    def get_conversion(object)
      bucket = @config.buckets.conversions
      Object.new(@client, @config, bucket, object)
    end
  end
end