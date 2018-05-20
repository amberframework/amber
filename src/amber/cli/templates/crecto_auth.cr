require "./auth"

module Amber::CLI
  class CrectoAuth < Auth
    directory "#{__DIR__}/auth/crecto"
  end
end
