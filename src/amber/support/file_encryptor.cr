require "./message_encryptor"

module Amber::Support
  class FileEncryptor
    def self.read(filename, encryption_key)
      new(encryption_key).read(filename)
    end

    def self.write(filename, body, encryption_key)
      new(encryption_key).write(filename, body)
    end

    def self.read_string(filename, encryption_key)
      new(encryption_key).read_as_string(filename)
    end

    getter encryption_key

    def initialize(@encryption_key : String)
      raise "Encryption key doesn't exist!" unless encryption_key
    end

    def read(filename : String)
      encryptor = Amber::Support::MessageEncryptor.new(encryption_key)
      encryptor.verify_and_decrypt(File.open(filename).gets_to_end.to_slice)
    end

    def write(filename : String, body : (String | Bytes))
      encryptor = MessageEncryptor.new(encryption_key)
      File.write(filename, encryptor.encrypt_and_sign(body))
    end

    def read_as_string(filename)
      String.new(read(filename))
    end
  end
end
