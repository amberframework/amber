require "./*"
require "../support/locale_formats"

# We are patching the String class and Number struct to extend the predicates
# available. This will allow to add friendlier methods for validation cases.
class String
  include Amber::Extension::String
end

abstract struct Number
  include Amber::Extension::Number
end

class HTTP::Server::Context
  include Amber::Extension::HTTPServerContext
end
