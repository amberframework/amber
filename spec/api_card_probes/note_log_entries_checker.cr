require "./probe_support"
require "log/spec"

Log.setup(:none)
Log.capture do |entries|
  Log.info { "API card probe" }
  entries.check(:info, /API card probe/)
end
