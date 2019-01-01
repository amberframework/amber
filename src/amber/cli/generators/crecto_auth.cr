require "./auth"

module Amber::CLI
  class CrectoAuth < Auth
    directory "#{__DIR__}/../templates/auth/crecto"
  end
end
