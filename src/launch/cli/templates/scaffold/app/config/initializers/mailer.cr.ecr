require "quartz_mailer"

Quartz.config do |c|
  c.smtp_enabled = Amber.settings.smtp.enabled

  c.smtp_address = ENV["SMTP_ADDRESS"]? || Amber.settings.smtp.host
  c.smtp_port = ENV["SMTP_PORT"]? || Amber.settings.smtp.port
  c.username = ENV["SMTP_USERNAME"]? || Amber.settings.smtp.username
  c.password = ENV["SMTP_PASSWORD"]? || Amber.settings.smtp.password

  c.use_authentication = !c.password.blank?
  c.use_tls = EMail::Client::TLSMode::NONE
  # c.use_tls = EMail::Client::TLSMode::STARTTLS
  # c.use_tls = EMail::Client::TLSMode::SMTPS
end

require "../../src/mailers/application_mailer"
require "../../src/mailers/**"
