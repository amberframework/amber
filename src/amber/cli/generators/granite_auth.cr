require "./auth"

module Amber::CLI
  class GraniteAuth < Auth
    directory "#{__DIR__}/../templates/auth/granite"
  end
end
