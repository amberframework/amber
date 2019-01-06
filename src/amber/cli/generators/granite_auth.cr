require "./auth"

module Amber::CLI
  class GraniteAuth < AuthBase
    directory "#{__DIR__}/../templates/auth/granite"
  end
end
