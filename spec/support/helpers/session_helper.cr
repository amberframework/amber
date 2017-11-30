module SessionHelper
  def create_session_config(store)
    Amber.settings.session = {
      "key"     => "name.session",
      "store"   => store,
      "expires" => 120,
    }
    Amber.settings.session
  end
end
