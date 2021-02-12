require "uri"
require "athena-config"

module Scalr::Config
  @[ACFA::Resolvable("server")]
  struct Server
    @allowed_host_regexes : Array(Regex)?

    @allowed_hosts : Array(String)?
    getter port : Int32 { ENV["SCALR_PORT"]?.try(&.to_i) || 3000 }

    def allowed_hosts
      @allowed_host_regexes ||= build_regexes
    end

    private def build_regexes
      allowed_hosts = @allowed_hosts ||
        ENV["SCALR_ALLOWED_HOSTS"]?.try(&.split(',').map(&.strip)) ||
        ["/.*/"]

      allowed_hosts.map do |host|
        (host[0] == '/' && host[-1] == '/') ?
          Regex.new(host[1..-2]) :
          /^#{Regex.escape(host)}$/
      end
    end
  end

  @[ACFA::Resolvable("s3")]
  struct S3
    getter region : String { ENV["AWS_DEFAULT_REGION"]? || "us-east-1" }
    getter key : String { ENV["AWS_ACCESS_KEY_ID"] }
    getter secret : String { ENV["AWS_SECRET_ACCESS_KEY"] }
    getter endpoint : URI? do
      ENV["AWS_ENDPOINT"]?.try { |value| URI.parse(value) }
    end
    getter public_endpoint : URI? do
      ENV["AWS_PUBLIC_ENDPOINT"]?.try { |value| URI.parse(value) } || endpoint
    end

    getter buckets : Scalr::Config::S3::Buckets = Scalr::Config::S3::Buckets.new

    struct Buckets
      getter originals : String { ENV["SCALR_BUCKET_ORIGINALS"]? || "scalr-originals" }
      getter conversions : String { ENV["SCALR_BUCKET_CONVERSIONS"]? || "scalr-conversions" }
    end
  end

  module URLConverter
    def from_yaml(ctx : YAML::ParseContext, node : YAML::Nodes::Node) : URI
      unless node.is_a?(YAML::Nodes::Scalar)
        node.raise "Expected scalar, not #{node.class}"
      end

      URI.parse(node.value)
    end

    extend self
  end
end

class Athena::Config::Base
  getter s3 = Scalr::Config::S3.new
  getter server = Scalr::Config::Server.new
end

