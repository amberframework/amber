require "http"
require "logger"
require "json"
require "colorize"
require "random/secure"
require "kilt"
require "kilt/slang"
require "redis"
require "environment"

require "./amber/version"
require "./amber/controller/**"
require "./amber/dsl/**"
require "./amber/exceptions/**"
require "./amber/extensions/**"
require "./amber/router/context"
require "./amber/pipes/**"
require "./amber/server/**"
require "./amber/validators/**"
require "./amber/websockets/**"

module Amber
  include Environment
end
