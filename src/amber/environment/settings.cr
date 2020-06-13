require "yaml"
require "yaml_mapping"

module Amber::Environment
  class Settings
    alias SettingValue = String | Int32 | Bool | Nil

    struct SMTPSettings
      property host = "127.0.0.1"
      property port = 1025
      property enabled = false
      property username = ""
      property password = ""
      property tls = false

      def self.from_hash(settings = {} of String => SettingValue) : self
        i = new
        i.host = settings["host"]? ? settings["host"].as String : i.host
        i.port = settings["port"]? ? settings["port"].as Int32 : i.port
        i.enabled = settings["enabled"]? ? settings["enabled"].as Bool : i.enabled
        i.username = settings["username"]? ? settings["username"].as String : i.username
        i.password = settings["password"]? ? settings["password"].as String : i.password
        i.tls = settings["tls"]? ? settings["tls"].as Bool : i.tls
        i
      end
    end

    setter session : Hash(String, Int32 | String)
    property database_url : String,
      host : String,
      name : String,
      port : Int32,
      port_reuse : Bool,
      process_count : Int32,
      redis_url : String?,
      secret_key_base : String,
      secrets : Hash(String, String),
      ssl_key_file : String,
      ssl_cert_file : String,
      logging : Logging::OptionsType

    property? auto_reload : Bool

    @smtp_settings : SMTPSettings?

    def smtp : SMTPSettings
      @smtp_settings ||= SMTPSettings.from_hash @smtp
    end

    YAML.mapping(
      logging: {
        type:    Logging::OptionsType,
        default: Logging::DEFAULTS,
      },
      database_url: {type: String, default: ""},
      host: {type: String, default: "localhost"},
      name: {type: String, default: "Amber_App"},
      port: {type: Int32, default: 3000},
      port_reuse: {type: Bool, default: true},
      process_count: {type: Int32, default: 1},
      redis_url: {type: String?, default: nil},
      secret_key_base: {type: String, default: Random::Secure.urlsafe_base64(32)},
      secrets: {type: Hash(String, String), default: Hash(String, String).new},
      session: {type: Hash(String, Int32 | String), default: {
        "key" => "amber.session", "store" => "signed_cookie", "expires" => 0,
      }},
      ssl_key_file: {type: String?, default: nil},
      ssl_cert_file: {type: String?, default: nil},
      smtp: {
        type:    Hash(String, SettingValue),
        getter:  false,
        default: Hash(String, SettingValue){
          "enabled" => false,
        },
      },
      auto_reload: {type: Bool, default: false}
    )

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

    def logging
      @_logging ||= Logging.new(@logging)
    end
  end
end
