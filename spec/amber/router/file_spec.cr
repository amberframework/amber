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
        ::File.basename(attachment.file.path).should end_with "yourfile.txt"
        attachment.file.delete
      end
    end
  end
end
