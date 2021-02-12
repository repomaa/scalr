require "pool"
require "awscr-s3"
require "../config"
require "../ext/awscr_client"
require "cache"

module Scalr::Services
  class S3
    DEFAULT_REGION = "us-east-1"
    DEFAULT_HOST = "s3.amazonaws.com"
    EXPIRES = 1.week.total_seconds.to_i.to_s

    @config : Config::S3

    class Object
      getter? exists
      getter? modified
      getter headers : HTTP::Headers

      def initialize(
        @config : Scalr::Config::S3,
        @bucket : String,
        @key : String,
        @clients : ::Pool(Awscr::S3::Client),
        @header_cache : Cache::MemoryStore(String, HTTP::Headers),
      )
        @modified = false
        @exists = true
        @cache = IO::Memory.new

        @headers = @header_cache.fetch("#{@bucket}/#{@key}") do
          with_client do |client|
            client.head_object(@bucket, @key).headers
          end
        rescue
          @exists = false
          HTTP::Headers.new
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
          with_client do |client|
            client.get_object(@bucket, @key) do |response|
              IO.copy(response.body_io, @cache)
            end
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

        with_client do |client|
          client.put_object(@bucket, @key, @cache.to_slice, headers: headers)
        end

        @exists = true
        @modified = true
      end

      def update_headers
        headers = {
          "x-amz-copy-source" => "/#{@bucket}/#{@key}",
          "x-amz-metadata-directive" => "REPLACE",
        }

        @headers.each do |key, values|
          downcased_key = key.downcase
          unless downcased_key == "content-type" || downcased_key.starts_with?("x-amz-meta-")
            next
          end

          headers[key] = values.first
        end

        with_client do |client|
          client.put_object(@bucket, @key, "", headers: headers)
        end

        @header_cache.write("#{@bucket}/#{@key}", @headers)
      end

      private def presign_request(request : HTTP::Request)
        with_client do |client|
          scope = Awscr::Signer::Scope.new(
            region: @config.region,
            service: "s3",
            timestamp: Time.utc.at_beginning_of_week
          )

          client.signer.presign(request, scope: scope)
        end
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

        request.query_params.add("X-Amz-Expires", EXPIRES)
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
        scheme = endpoint.scheme
        port = endpoint.port
        port.nil? || scheme == "http" && port == 80 || scheme == "https" && port == 443
      end

      private def with_client(&block : Awscr::S3::Client -> T) : T forall T
        @clients.get { |client| return yield client }
        raise "connection pool didn't yield"
      end
    end

    def initialize(@config : Scalr::Config::S3)
      @clients = Pool(Awscr::S3::Client).new do
        Awscr::S3::Client.new(
          region: @config.region,
          aws_access_key: @config.key,
          aws_secret_key: @config.secret,
          endpoint: @config.endpoint.to_s,
        )
      end

      @header_cache = Cache::MemoryStore(String, HTTP::Headers).new(
        expires_in: 10.minutes,
      )
    end

    def get_original(object)
      bucket = @config.buckets.originals
      Object.new(@config, bucket, object, @clients, @header_cache)
    end

    def get_conversion(object)
      bucket = @config.buckets.conversions
      Object.new(@config, bucket, object, @clients, @header_cache)
    end
  end
end
