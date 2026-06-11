require "./mailer/email"
require "./mailer/delivery_adapter"
require "./mailer/mime"
require "./mailer/configuration"
require "./mailer/memory_adapter"
require "./mailer/smtp_adapter"
require "./mailer/base"

module Amber::Mailer
  # Amber's built-in email delivery system.
  #
  # Provides a complete mailer framework with an adapter pattern for
  # pluggable delivery backends. Ships with a memory adapter for testing
  # and an SMTP adapter for production use.
  #
  # ## Quick Start
  #
  # Define a mailer:
  #
  # ```
  # class WelcomeMailer < Amber::Mailer::Base
  #   def initialize(@user_name : String, @user_email : String)
  #   end
  #
  #   def html_body : String?
  #     "<h1>Welcome, #{HTML.escape(@user_name)}!</h1>"
  #   end
  #
  #   def text_body : String?
  #     "Welcome, #{@user_name}!"
  #   end
  # end
  # ```
  #
  # Send an email:
  #
  # ```
  # WelcomeMailer.new("Alice", "alice@example.com")
  #   .to("alice@example.com")
  #   .from("hello@myapp.com")
  #   .subject("Welcome!")
  #   .deliver
  # ```
  #
  # ## Configuration
  #
  # ```
  # Amber::Mailer::Configuration.configure do |config|
  #   config.adapter = :smtp
  #   config.smtp_host = "smtp.example.com"
  #   config.smtp_port = 587
  #   config.smtp_username = ENV["SMTP_USER"]
  #   config.smtp_password = ENV["SMTP_PASS"]
  #   config.use_tls = true
  #   config.default_from = "noreply@myapp.com"
  # end
  # ```
end
