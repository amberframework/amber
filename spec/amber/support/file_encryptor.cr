require "../../../spec_helper"

describe Amber::Support::FileEncryptor do
  Dir.mkdir_p("./tmp")
  context "#encryption_key" do
    it "load encryption_key from ENV variable" do
      ENV[Amber::SECRET_KEY] = "fake encryption key"
      Amber::Support::FileEncryptor.encryption_key.should eq "fake encription key"
    end

    it "load encryption_key from .encryption_key file" do
      ENV[Amber::SECRET_KEY] = nil
      File.write(Amber::SECRET_FILE, "fake secret key")
      Amber::Support::FileEncryptor.encryption_key.should eq "fake secret key"

      # TODO: This is dangerous as this file could be left over.
      File.delete(Amber::SECRET_FILE)
    end
  end

  context "read and write global_key" do
    ENV[Amber::SECRET_KEY] = "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw"

    it "writes and encrypted file" do
      Amber::Support::FileEncryptor.write("./tmp/testenc.enc", "name: elorest")
      File.exists?("./tmp/testenc.enc").should be_truthy
    end

    it "reads encrypted file" do
      result = String.new(Amber::Support::FileEncryptor.read("./tmp/testenc.enc"))
      result.should eq "name: elorest"
    end

    it "reads encrypted file to string" do
      result = Amber::Support::FileEncryptor.read_as_string("./tmp/testenc.enc")
      result.should eq "name: elorest"
    end
  end

  context "read and write with specified key" do
    ENV[Amber::SECRET_KEY] = nil
    it "writes and encrypted file" do
      Amber::Support::FileEncryptor.write("./tmp/testenc.enc", "name: elorest", "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw")
      File.exists?("./tmp/testenc.enc").should be_truthy
    end

    it "reads encrypted file" do
      result = String.new(Amber::Support::FileEncryptor.read("./tmp/testenc.enc", "mnDiAY4OyVjqg5u0wvpr0MoBkOGXBeYo7_ysjwsNzmw"))
      result.should eq "name: elorest"
    end
  end
end
