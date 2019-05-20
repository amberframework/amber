require "../config/application"

Amber::Support::ClientReload.new if Amber.settings.auto_reload?
Amber::Server.load_manifest
Amber::Server.start
