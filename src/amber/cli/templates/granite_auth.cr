require "./auth"

module Amber::CLI
  class GraniteAuth < Auth
    directory "#{__DIR__}/auth/granite"
  end
end
