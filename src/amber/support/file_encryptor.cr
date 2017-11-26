require "./message_encryptor"

module Amber::Support
  module FileEncryptor
    def self.global_encryption_key
      ENV["AMBER_ENCRYPTION_KEY"]? || begin
        if File.exists?(".encryption_key")
          File.open(".encryption_key").gets_to_end.to_s
        else
          nil
        end
      end
    end

    def self.read(filename : String, encryption_key = global_encryption_key)
      if encryption_key
        encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
        encryptor.verify_and_decrypt(File.open(filename).gets_to_end.to_slice)
      else
        raise "Encryption key doesn't exist!"
      end
    end

    def self.write(filename : String, body : (String | Bytes), encryption_key = global_encryption_key)
      if encryption_key
        encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
        File.write(filename, encryptor.encrypt_and_sign(body))
      else
        raise "Encryption key doesn't exist!"
      end
    end
  end
end
