require "http"
require "logger"
require "json"
require "colorize"
require "random/secure"
require "kilt"
require "kilt/slang"
require "redis"
require "./amber/version"
require "./amber/controller/**"
require "./amber/dsl/**"
require "./amber/exceptions/**"
require "./amber/extensions/**"
require "./amber/router/**"
require "./amber/server/**"
require "./amber/validations/**"
require "./amber/websockets/**"
require "./amber/environment"

module Amber
  include Amber::Environment
end
