module SessionHelper
  def create_session_config(store)
    Launch.settings.session = {
      "key"     => "name.session",
      "store"   => store,
      "expires" => 120,
    }
    Launch.settings.session
  end
end
