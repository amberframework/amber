require "../config/application"

Amber::Support::ClientReload.new if Amber.settings.auto_reload?
Amber::Support::Assets.load_manifest
Amber::Server.start
