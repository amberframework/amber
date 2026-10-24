require "../../spec_helper"

module Amber::Router
  describe File do
    it "supports the upload of a file with a path as the filename" do
      formdata = <<-FORMDATA
    -----------------------------735323031399963166993862150
    Content-Disposition: form-data; name="yourfile.txt"; filename="/home/somewhere/yourfile.txt"
    text
    -----------------------------735323031399963166993862150--
    FORMDATA

      parser = HTTP::FormData::Parser.new IO::Memory.new(formdata.gsub('\n', "\r\n")), "---------------------------735323031399963166993862150"
      parser.next do |part|
        attachment = Amber::Router::File.new(upload: part)
        attachment.filename.should eq "/home/somewhere/yourfile.txt"
        ::File.basename(attachment.file.path).should start_with "amber-upload"
        ::File.basename(attachment.file.path).should end_with ".txt"
        attachment.file.delete
      end
    end

    it "keeps the tempfile name independent of an untrusted filename" do
      long_name = "#{"a" * 300}.txt"
      formdata = "--AmberBoundary\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"#{long_name}\"\r\n\r\ntext\r\n--AmberBoundary--\r\n"

      parser = HTTP::FormData::Parser.new IO::Memory.new(formdata), "AmberBoundary"
      parser.next do |part|
        attachment = Amber::Router::File.new(upload: part)
        attachment.filename.should eq long_name
        ::File.basename(attachment.file.path).bytesize.should be < 64
        attachment.delete_tempfile
        ::File.exists?(attachment.file.path).should be_false
      end
    end

    it "keeps only a plain extension" do
      File.safe_extension("photo.JPG").should eq ".JPG"
      File.safe_extension("archive.tar.gz").should eq ".gz"
      File.safe_extension("weird.ex/t").should eq ""
      File.safe_extension("noextension").should eq ""
      File.safe_extension(nil).should eq ""
    end
  end
end
