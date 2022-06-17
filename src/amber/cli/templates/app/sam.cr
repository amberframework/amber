require "./config/*"
require "./db/migrations/*"
require "sam"
load_dependencies "jennifer"

## Add custom tasks to run here, make sure to add the commands to the amber.yml as well!

Sam.help
