require "../support/message_encryptor"

environment = ARGV[0]? || ENV["AMBER_ENV"]?
secret_key = ENV["AMBER_SECRET_KEY"]? || begin
  File.open(".amber_secret_key").gets_to_end.to_s if File.exists?(".amber_secret_key")
end

yml = if File.exists?("#{environment}.yml")
        File.read("#{environment}.yml")
      elsif File.exists?(".#{environment}.enc") && secret_key
        enc = Amber::Support::MessageEncryptor.new(secret_key.to_slice)
        String.new(enc.decrypt(File.open(".#{environment}.enc").gets_to_end.to_slice))
      else
        "env: #{environment}"
      end 
secrets = YAML.parse(yml)
puts "property ntup = #{secrets.inspect.gsub(/(\"[^\"]+\") \=\>/) { "#{$1}:" }}" 
