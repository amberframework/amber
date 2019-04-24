require "./auth"

module Amber::CLI
  class ClearAuth < AuthBase
    directory "#{__DIR__}/../templates/auth/clear"
  end
end
