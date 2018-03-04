require "./field.cr"

module Amber::CLI
  class Sam < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/sam"
  end
end
