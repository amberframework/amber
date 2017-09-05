require "./cluster"
require "./configuration"
require "./ssl"

module Amber
  class Settings
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class

    getter handler = Pipe::Pipeline.new
    getter router = Router::Router.new
    getter secret_key_base = SecureRandom.urlsafe_base64(32)
    getter key_generator = Amber::Support::CachingKeyGenerator.new(
      Amber::Support::KeyGenerator.new(@secret_key_base.to_s, 5)
    )

    property env : String
    property host : String
    property name : String
    property log : ::Logger = ::Logger.new(STDOUT)
    property redis_url : String?
    property process_count : Int32
    property port_reuse : Bool
    property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    property session : Hash(String, Int32 | String)
    property ssl_key_file : String?
    property ssl_cert_file : String?
    property secrets : Hash(String, String)

    YAML.mapping(
      env: {type: String, default: "development"},
      host: {type: String, default: "localhost"},
      name: {type: String, default: "Amber_App"},
      redis_url: {type: String?, default: nil},
      port_reuse: {type: Bool, default: true},
      port: {type: Int32, default: 3000},
      process_count: {type: Int32, default: 1},
      secret_key_base: {type: String, default: SecureRandom.urlsafe_base64(32)},
      ssl_key_file: {type: String?, default: nil},
      ssl_cert_file: {type: String?, default: nil},
      secrets: {type: Hash(String, String), default: {} of String => String},
      session: {type: Hash(String, Int32 | String), default: {
        "key" => "amber.session", "store" => "signed_cookie", "expires" => 0,
      }},
    )
  end
end
