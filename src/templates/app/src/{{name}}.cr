# Location for your initialization code
# {YourApp}/src/config/app.cr

# The config file that Amber generates, web/router.cr, will look something like
# this one:

# The first line requires the framework library.
require "amber"
require "./**"
require "./*"
require "../config/*"

Amber::Server.instance.run
