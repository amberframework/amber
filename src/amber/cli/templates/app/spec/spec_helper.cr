ENV["AMBER_ENV"] ||= "test"

require "spec"
require "micrate"
require "garnet_spec"

require "../config/*"

Micrate::DB.connection_url = Amber.settings.database_url

# Automatically run migrations on the test database
Micrate::Cli.run_up

# Disable query logger for tests
Granite::ORM.settings.logger = Logger.new nil

module Spec
  DRIVER = :chrome
  PATH   = "/usr/local/bin/chromedriver"

  # Not all server implementations will support every WebDriver feature.
  # Therefore, the client and server should use JSON objects with the properties
  # listed below when describing which features a session supports.
  capabilities = {
    browserName:              "chrome",
    version:                  "",
    platform:                 "ANY",
    javascriptEnabled:        true,
    takesScreenshot:          true,
    handlesAlerts:            true,
    databaseEnabled:          true,
    locationContextEnabled:   true,
    applicationCacheEnabled:  true,
    browserConnectionEnabled: true,
    cssSelectorsEnabled:      true,
    webStorageEnabled:        true,
    rotatable:                true,
    acceptSslCerts:           true,
    nativeEvents:             true,
    args:                     "--headless",
  }
end
