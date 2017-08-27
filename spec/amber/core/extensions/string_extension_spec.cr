require "../../../spec_helper"

module Amber::Extensions
  describe StringExtension do
    it "returns true on valid email address" do
      "info@burakdemirtas.org".email?.should eq(true)
      "info@crystal-lang.com".email?.should eq(true)
      "test@mail.co".email?.should eq(true)
    end

    it "returns true on valid domain name" do
      "amberci.io".domain?.should eq(true)
      "www.amberci.com".domain?.should eq(true)
      "www.amber-crystal.com".domain?.should eq(true)
    end

    it "returns true for valid URI" do
      "https://www.crystal-lang.com/".url?.should eq(true)
      "https://crystal-lang.com/api/".url?.should eq(true)
      "https://crystal-lang.org/docs/overview/http_server.html".url?.should eq(true)
      "https://crystal-lang.org/?page=demo&id=17".url?.should eq(true)
    end

    it "returns true for valid ALPHA charecters" do
      "WeLoveCrystal".alpha?.should eq(true)
      "İzniBurakDemirtaş".alpha?("tr-TR").should eq(true)
    end

    it "returns true for valid ALPHA NUMERIC characters" do
      "Burak17".alphanum?.should eq(true)
      "İzni17Burak25Demirtaş".alphanum?("tr-TR").should eq(true)
    end

    it "returns true for NUMERIC characters" do
      "789716398719378213".numeric?.should eq(true)
      "a79837129879".numeric?.should eq(false)
    end

    it "returns true for all lowercase string" do
      "izniburak".lower?.should eq(true)
      "Crystal".lower?.should eq(false)
    end
    it "returns true for all uppercase string" do
      "BURAK".upper?.should eq(true)
      "CRySTaL".upper?.should eq(false)
    end

    it "returns true for valid HEX color" do
      "#f0f".hex_color?.should eq(true)
      "#a1b2c3".hex_color?.should eq(true)
    end

    it "returns true for valid hexa decimal number" do
      "0x17b".hex?.should eq(true)
      "0acdadecf822eeff32aca58".hex?.should eq(true)
      "8DABF30C".hex?.should eq(true)
    end

    it "returns true for locale phone number format" do
      "5066072221".phone?("tr-TR").should eq(true)
      "05066072221".phone?("tr-TR").should eq(true)
      "+905066072221".phone?("tr-TR").should eq(true)
    end

    it "returns true for valid time string" do
      "13:45:30".time_string?.should eq(true)
    end

    it "returns true for base64 string" do
      "d2UgbG92ZSBjcnlzdGFsIQ==".base64?.should eq(true)
    end

    it "returns true for valid MD5 hash string" do
      "39109a5bb10ccb7aff1313d369804b74".md5?.should eq(true)
    end
  end
end
