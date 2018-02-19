require "./message_encryptor"

module Amber::Support
  ENCRYPT_ENV = "AMBER_ENCRYPTION_KEY"
  FILE_PATH   = "./.encryption_key"

  module FileEncryptor
    def self.read(filename : String, encryption_key = self.encryption_key)
      encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
      encryptor.verify_and_decrypt(File.open(filename).gets_to_end.to_slice)
    end

    def self.write(filename : String, body : (String | Bytes), encryption_key = self.encryption_key)
      encryptor = MessageEncryptor.new(encryption_key)
      File.write(filename, encryptor.encrypt_and_sign(body))
    end

    def self.read_as_string(filename, encryption_key = self.encryption_key)
      String.new(read(filename, encryption_key))
    end

    def self.encryption_key(file = FILE_PATH)
      ENV[ENCRYPT_ENV]? || File.open(file).read_line
    rescue
      raise Amber::Exceptions::EncryptionKeyMissing.new(file, ENCRYPT_ENV)
    end
  end
end
