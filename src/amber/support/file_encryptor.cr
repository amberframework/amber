require "./message_encryptor"

module Amber::Support
  SECRET_KEY  = "AMBER_ENCRYPTION_KEY"
  SECRET_FILE = "./.encryption_key"

  module FileEncryptor
    def self.read(filename : String, encryption_key = encryption_key)
      encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
      encryptor.verify_and_decrypt(File.open(filename).gets_to_end.to_slice)
    end

    def self.write(filename : String, body : (String | Bytes), encryption_key = encryption_key)
      encryptor = MessageEncryptor.new(encryption_key)
      File.write(filename, encryptor.encrypt_and_sign(body))
    end

    def self.read_as_string(filename, encryption_key = encryption_key)
      String.new(read(filename, encryption_key))
    end

    private def self.encryption_key
      ENV[SECRET_KEY]? || File.open(SECRET_FILE).gets_to_end.to_s
    end
  end
end
