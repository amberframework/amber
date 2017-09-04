require "yaml"
require "secure_random"
require "../support/message_encryptor"

puts "********************************************************************************"
puts "********************************************************************************"
puts ENV["AMBER_ENV"]?
puts "********************************************************************************"
puts "********************************************************************************"
puts "********************************************************************************"

environment = ARGV[0]? || ENV["AMBER_ENV"]? || "development"
env_path = ENV["AMBER_ENV_PATH"]? || "./config/environments" 
secret_key = ENV["AMBER_SECRET_KEY"]? || begin
  File.open(".amber_secret_key").gets_to_end.to_s if File.exists?(".amber_secret_key")
end

yml = if File.exists?(fn = "#{env_path}/#{environment}.yml")
        File.read(fn)
      elsif File.exists?(fn = "#{env_path}/.#{environment}.enc") && secret_key
        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)
        String.new(enc.decrypt(File.open(fn).gets_to_end.to_slice))
      else
        "env: #{environment}"
      end

settings = YAML.parse(yml)

str = String.build do |s|
  # Most of this logic can be cleaned up by just requiring environment files to contain valid params.
  # For now I have this here so that tests can still pass without having to load env files although they should.
  # This is a transistion.
  s.puts %(@@name = "#{settings["name"]? || "Amber_App"}")
  s.puts %(@@port_reuse = #{settings["port_reuse"]? || true})
  s.puts %(@@process_count = #{settings["process_count"]? || 1})
  s.puts %(@@log = #{settings["log"]? || "::Logger.new(STDOUT)"})
  s.puts %(@@log.level = #{settings["log_level"]? || "::Logger::INFO"})
  s.puts %(@@redis_url = "#{settings["redis_url"]? ||"redis://localhost:6379"}")
  s.puts %(@@port = #{settings["port"]? || 3000})
  s.puts %(@@host = "#{settings["host"]? || "127.0.0.1"}")
  s.puts %(@@secret_key_base = "#{settings["secret_key_base"]? || SecureRandom.urlsafe_base64(32)}")

  unless settings["ssl_key_file"]?.to_s.empty?
    s.puts %(@@ssl_key_file = "#{settings["ssl_key_file"]?}")
  end

  unless settings["ssl_cert_file"]?.to_s.empty?
    s.puts %(@@ssl_cert_file = "#{settings["ssl_cert_file"]?}")
  end

  if settings["session"]? && settings["session"].raw.is_a?(Hash(YAML::Type, YAML::Type))
    s.puts %(@@session = #{settings["session"].inspect.gsub(/(\"[^\"]+\" \=\>)/) { ":#{$1}".gsub("\"", "") }})
  else
    s.puts %(@@session = {:key => "amber.session", :store => "signed_cookie", :expires => "0"})
  end

  if settings["secrets"]? && settings["secrets"].raw.is_a?(Hash(YAML::Type, YAML::Type))
    s.puts "class_getter secrets = #{settings["secrets"].inspect.gsub(/(\"[^\"]+\") \=\>/) { "#{$1}:" }}"
  else
    s.puts %(class_getter secrets = {description: "Store your #{environment} secrets credentials and settings here."})
  end
end

puts str
