# Shared machinery for every Mica format: errors with positions, work
# budgets and deadlines, UTF-8 and transcoding, buffered input and line
# tracking. See docs/ADDING_A_FORMAT.md for how a format plugs in.
module Amber::Mica::Core
end

require "./core/position"
require "./core/error"
require "./core/excerpt"
require "./core/work_budget"
require "./core/utf8"
require "./core/encoding"
require "./core/transcoder"
require "./core/byte_input"
require "./core/text_input"
require "./core/line_tracking"
require "./core/byte_search"
require "./core/byte_scan"
