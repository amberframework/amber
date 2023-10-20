module SessionHelper
  def create_session_config(store)
    Amber.settings.session_key = "name.session"
    Amber.settings.session_store = store
    Amber.settings.session_expires = 120

    Amber.settings.session
  end
end
