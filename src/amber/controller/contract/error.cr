module Contract
  class Error < Exception
    getter errors : Array(Error)

    def initialize(@errors)
    end
  end
end
