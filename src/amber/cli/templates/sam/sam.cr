require "./config/*"
require "sam"

#
# This is a Sam file. Place your tasks here or in separate files and load them
# explicitly. To load any package defined Sam task - use:
#
# load_dependencies "package_name"
#
# Here is an example of simple Sam task:
#
# Sam.namespace "simon" do
#   task "says" do |t, args|
#     puts args[0]
#   end
# end
#
# To invoke this task use:
# $ amber sam simon:says "Get happy codding with Amber"
#
# For the following reading visit the https://github.com/imdrasil/sam.cr.
#

Sam.help
