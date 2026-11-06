require "./probe_support"

Amber::Server.configure do
  pipeline :auth_token do
  end
end
