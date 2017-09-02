require "yaml"
require "../support/message_encryptor"

environment = ARGV[0]? || ENV["AMBER_ENV"]? || "development"
secret_key = ENV["AMBER_SECRET_KEY"]? || begin
  File.open(".amber_secret_key").gets_to_end.to_s if File.exists?(".amber_secret_key")
end

yml = if File.exists?(fn = "config/environments/#{environment}.yml")
        File.read(fn)
      elsif File.exists?(fn = "config/environments/.#{environment}.enc") && secret_key
        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)
        String.new(enc.decrypt(File.open(fn).gets_to_end.to_slice))
      else
        "env: #{environment}"
      end
secrets = YAML.parse(yml)

puts %(@@name = "#{secrets["name"] || "amber server"}")
puts "@@port = #{secrets.delete("port")}" if secrets["port"]?
puts "@@pubsub_adapter = WebSockets::Adapters::RedisAdapter"
puts "class_property secrets = #{secrets.inspect.gsub(/(\"[^\"]+\") \=\>/) { "#{$1}:" }}"
