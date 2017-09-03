require "./cluster"
require "./configuration"
require "./ssl"

module Amber
  class Settings
    include Amber::DSL::Server
    alias WebSocketAdapter = WebSockets::Adapters::RedisAdapter.class | WebSockets::Adapters::MemoryAdapter.class
    class_getter handler = Pipe::Pipeline.new
    class_getter router = Router::Router.new
    class_property pubsub_adapter : WebSocketAdapter = WebSockets::Adapters::MemoryAdapter
    class_property port_reuse : Bool 
    class_property log : ::Logger
    class_property env = ENV["AMBER_ENV"]? || "development"
    class_property process_count : Int32 
    class_property secret_key_base : String 
    class_property port : Int32 
    class_property name : String
    class_property host : String
    class_property ssl_key_file : String? = nil
    class_property ssl_cert_file : String? = nil
    class_property redis_url = "" 
    class_property session : Hash(Symbol, String) 

    #loads settings from environment yaml
    {{ run("./environment.cr") }}

    #TODO: Remove as ASAP!
    class_getter key_generator = Amber::Support::CachingKeyGenerator.new(
      Amber::Support::KeyGenerator.new(@@secret_key_base.to_s, 5)
    )
  end
end
