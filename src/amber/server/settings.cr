module Amber
  class Settings
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class
    class_property port_reuse = true
    class_getter handler = Pipe::Pipeline.new
    class_getter router = Router::Router.new
    class_property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    class_property log = ::Logger.new(STDOUT)
    class_property env = ENV["AMBER_ENV"]? || "development"
    class_property process_count = 1
    class_property secret_key_base = SecureRandom.urlsafe_base64(64)
    class_property port = 8080
    class_property name = "amber_project"
    class_property host = "0.0.0.0"
    class_property ssl_key_file : String? = nil
    class_property ssl_cert_file : String? = nil
    class_property redis_url = ""
    class_property session = {
      :key => "amber.session", :store => :signed_cookie, :expires => 0
    }
    class_getter key_generator = Amber::Support::CachingKeyGenerator.new(
      Amber::Support::KeyGenerator.new(@@secret_key_base.to_s, 5)
    )
    load_environment
  end
end
