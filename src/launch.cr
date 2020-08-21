require "http"
require "log"
require "json"
require "colorize"
require "random/secure"
require "kilt"
require "kilt/slang"
require "redis"
require "compiled_license"

require "./launch/version"
require "./launch/controller/**"
require "./launch/dsl/**"
require "./launch/exceptions/**"
require "./launch/extensions/**"
require "./launch/router/context"
require "./launch/pipes/**"
require "./launch/server/**"
require "./launch/validators/**"
require "./launch/websockets/**"
require "./launch/environment"

module Launch
  include Launch::Environment
end
