require "./auth"

module Amber::CLI
  class CrectoAuth < AuthBase
    directory "#{__DIR__}/../templates/auth/crecto"
  end
end
