require "citrine-i18n"

Citrine::I18n.configure do |settings|
  # Backend storage (as supported by i18n.cr)
  # settings.backend = I18n::Backend::Yaml.new

  # Default locale (defaults to "en" and "./src/locales/**/en.yml").
  # For a new default locale to be accepted, it must be found by the
  # backend storage and reported in "settings.available_locales".
  # settings.default_locale = "en"

  # Separator between sublevels of data (defaults to '.')
  # e.g. I18n.translate("some/thing") instead of "some.thing"
  # settings.default_separator = '.'

  # Returns the current exception handler. Defaults to an instance of
  # I18n::ExceptionHandler.
  # settings.exception_handler = ExceptionHandler.new

  # The path from where the translations should be loaded
  settings.load_path += ["./src/locales"]
end

I18n.init
