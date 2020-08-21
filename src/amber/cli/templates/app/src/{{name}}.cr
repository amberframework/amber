require "../config/application"

Launch::Support::ClientReload.new if Launch.settings.auto_reload?
Launch::Server.start
