module Amber::Beryl
  # The base of every error Beryl raises. Rescue this to handle any failure
  # that comes from the shard.
  class Error < Exception
  end
end
