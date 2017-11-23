require "./cluster"
require "./ssl"

module Amber
  class Settings
    include Amber::DSL::Server
    property log : ::Logger = Logger.new(STDOUT)

    property colorize_logging : Bool = true
    property database_url = ""
    property host : String = "localhost"
    property name : String = "Amber_App"
    property port : Int32 = 3000
    property port_reuse : Bool = true
    property process_count : Int32 = 1
    property redis_url = ""
    property secret_key_base : String = SecureRandom.urlsafe_base64(32)
    setter session : Hash(String, Int32 | String) = {
      "key" => "amber.session", "store" => "signed_cookie", "expires" => 0,
    }
    property secrets : Hash(String, String)?
    property ssl_key_file : String?
    property ssl_cert_file : String?

    YAML.mapping(
      colorize_logging: {type: Bool, default: true},
      database_url: {type: String?, default: nil},
      host: {type: String, default: "localhost"},
      name: {type: String, default: "Amber_App"},
      port: {type: Int32, default: 3000},
      port_reuse: {type: Bool, default: true},
      process_count: {type: Int32, default: 1},
      redis_url: {type: String?, default: nil},
      secret_key_base: {type: String, default: SecureRandom.urlsafe_base64(32)},
      secrets: {type: Hash(String, String)?},
      session: {type: Hash(String, Int32 | String), default: {
        "key" => "amber.session", "store" => "signed_cookie", "expires" => 0,
      }},
      ssl_key_file: {type: String?, default: nil},
      ssl_cert_file: {type: String?, default: nil},
    )

    def initialize
    end

    def session
      {
        :key     => @session["key"].to_s,
        :store   => session_store,
        :expires => @session["expires"].to_i,
      }
    end

    def session_store
      case @session["store"].to_s
      when "signed_cookie" then :signed_cookie
      when "redis"         then :redis
      else                      "encrypted_cookie"
      :encrypted_cookie
      end
    end
  end
end
