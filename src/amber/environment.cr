module Amber::Environment
  macro included
    class_property environments = {"development" => DefaultConfig.new, "test" => DefaultConfig.new, "production" => DefaultConfig.new}

    class DefaultConfig
      property secret_key_base = "abcdefghijklmnopqrstuvwxyz123456"
      property port = 3000
      property name = "default app name"

      property logging_severity = "debug"
      property logging_colorize = true
      property logging_filter = ["password", "confirm_password"]
      property logging_skip = [] of String

      property host = "0.0.0.0"
      property port_reuse = true
      property process_count = 1

      # ssl_key_file:
      # ssl_cert_file:

      property redis_url = "redis://localhost:6379"
      property database_url = ""
      property auto_reload = true

      property session_key = "amber.session"
      property session_store = "signed_cookie"
      property session_expires = 0

      property smtp_enabled = false
      property pipes_static_headers = {"Cache-Control" => "no-store"}
    end

    def self.settings
      environments[ENV["AMBER_ENV"]]
    end
  end
end
