require "./message_encryptor"

module Amber::Support
  module FileEncryptor
    def self.encryption_key
      ENV["AMBER_ENCRYPTION_KEY"]? || begin
        if File.exists?(".encryption_key")
          File.open(".encryption_key").gets_to_end.to_s
        else
          raise Exceptions::EncryptionKeyMissing.new
        end
      end
    end

    def self.read(filename : String, encryption_key = self.encryption_key)
      encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
      encryptor.verify_and_decrypt(File.open(filename).gets_to_end.to_slice)
    end

    def self.write(filename : String, body : (String | Bytes), encryption_key = self.encryption_key)
      encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
      File.write(filename, encryptor.encrypt_and_sign(body))
    end

    def self.read_as_string(filename, encryption_key = self.encryption_key)
      String.new(read(filename, encryption_key))
    end
  end
end
