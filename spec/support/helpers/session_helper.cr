module SessionHelper
  def create_session_config(store)
    Amber::Server.settings.session = {
      "key"     => "name.session",
      "store"   => store,
      "expires" => 120,
    }
    Amber::Server.settings.session
  end
end
