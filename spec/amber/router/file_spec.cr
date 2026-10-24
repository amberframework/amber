require "../../spec_helper"
require "file_utils"

private def build_upload(content : String) : Amber::Router::File
  boundary = "FileSpecBoundary"
  body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"a.txt\"\r\n\r\n#{content}\r\n--#{boundary}--\r\n"
  parser = HTTP::FormData::Parser.new(IO::Memory.new(body), boundary)
  attachment = nil
  parser.next { |part| attachment = Amber::Router::File.new(upload: part) }
  attachment || raise "the multipart body had no part"
end

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
        ::File.basename(attachment.path).should start_with "amber-upload"
        ::File.basename(attachment.path).should end_with ".txt"
        attachment.delete_tempfile
      end
    end

    it "keeps the tempfile name independent of an untrusted filename" do
      long_name = "#{"a" * 300}.txt"
      formdata = "--AmberBoundary\r\nContent-Disposition: form-data; name=\"doc\"; filename=\"#{long_name}\"\r\n\r\ntext\r\n--AmberBoundary--\r\n"

      parser = HTTP::FormData::Parser.new IO::Memory.new(formdata), "AmberBoundary"
      parser.next do |part|
        attachment = Amber::Router::File.new(upload: part)
        attachment.filename.should eq long_name
        ::File.basename(attachment.path).bytesize.should be < 64
        attachment.delete_tempfile
        ::File.exists?(attachment.path).should be_false
      end
    end

    it "keeps the upload readable through file until Amber's cleanup closes and deletes it" do
      attachment = build_upload("file body")
      attachment.file.gets_to_end.should eq "file body"
      handle = attachment.file

      attachment.delete_tempfile

      handle.closed?.should be_true
      ::File.exists?(attachment.path).should be_false
    end

    it "shares ownership across copies, as params.files hands out copies" do
      files = {"doc" => build_upload("file body")}
      kept_path = files["doc"].retain!

      files["doc"].owned_by_amber?.should be_false
      files["doc"].delete_tempfile
      ::File.read(kept_path).should eq "file body"
      ::File.delete(kept_path)
    end

    it "moves an upload out of Amber's cleanup with move_to" do
      attachment = build_upload("file body")
      attachment.file.gets_to_end
      destination = ::File.tempname("amber-kept-upload", ".txt")

      attachment.move_to(destination).should eq destination
      attachment.delete_tempfile

      ::File.read(destination).should eq "file body"
      ::File.exists?(attachment.path).should be_false
      expect_raises(IO::Error, /moved/) { attachment.file }
      expect_raises(IO::Error, /already moved or retained/) { attachment.retain! }
      ::File.delete(destination)
    end

    it "leaves both files intact when a cross-file-system copy fails" do
      attachment = build_upload("upload body")
      directory = ::File.tempname("amber-move-spec")
      Dir.mkdir(directory)
      destination = ::File.join(directory, "kept.txt")
      ::File.write(destination, "existing content")
      failing_copy = ->(from : IO, to : IO) do
        to.write(from.read_string(3).to_slice)
        raise IO::Error.new("No space left on device")
      end

      expect_raises(IO::Error, /No space left/) do
        attachment.open_tempfile { |source| File.copy_into_place(source, destination, failing_copy) }
      end

      ::File.read(destination).should eq "existing content"
      ::File.read(attachment.path).should eq "upload body"
      attachment.owned_by_amber?.should be_true
      Dir.children(directory).should eq ["kept.txt"]
      attachment.delete_tempfile
      FileUtils.rm_rf(directory)
    end

    it "renames a completed cross-file-system copy into place" do
      attachment = build_upload("upload body")
      directory = ::File.tempname("amber-move-spec")
      Dir.mkdir(directory)
      destination = ::File.join(directory, "kept.txt")
      ::File.write(destination, "existing content")

      attachment.open_tempfile { |source| File.copy_into_place(source, destination) }

      ::File.read(destination).should eq "upload body"
      Dir.children(directory).should eq ["kept.txt"]
      attachment.delete_tempfile
      FileUtils.rm_rf(directory)
    end

    it "deletes a discarded file even when closing it fails" do
      file = ::File.tempfile("amber-discard-spec")
      file.print "unflushed"
      # Closing the descriptor underneath makes the File's own close fail.
      LibC.close(file.fd)

      File.discard(file)

      ::File.exists?(file.path).should be_false
    end

    it "uses a new private directory when the shared one is not private" do
      shared = File::UPLOAD_DIRECTORY
      File.upload_directory
      ::File.chmod(shared, 0o755)
      begin
        fallback = File.upload_directory
        fallback.should_not eq shared
        info = ::File.info(fallback, follow_symlinks: false)
        (info.permissions.value & 0o077).should eq 0
        File.upload_directory.should eq fallback
      ensure
        ::File.chmod(shared, 0o700)
      end
    end

    it "keeps a retained upload at its path for later use" do
      attachment = build_upload("for a job")
      path = attachment.retain!

      attachment.delete_tempfile

      path.should eq attachment.path
      ::File.read(path).should eq "for a job"
      expect_raises(IO::Error, /already moved or retained/) { attachment.move_to(::File.tempname) }
      ::File.delete(path)
    end

    it "leaves a file that replaced the tempfile at its path" do
      attachment = build_upload("original")
      # Written while the tempfile still exists, so it has its own inode.
      replacement = ::File.join(File.upload_directory, "replacement-#{Random::Secure.hex(8)}")
      ::File.write(replacement, "replacement")
      ::File.rename(replacement, attachment.path)

      attachment.delete_tempfile

      ::File.read(attachment.path).should eq "replacement"
      ::File.delete(attachment.path)
    end

    it "reuses one private upload directory owned by this user" do
      directory = File.upload_directory
      File.upload_directory.should eq directory
      ::File.basename(directory).should start_with "amber-uploads"

      info = ::File.info(directory, follow_symlinks: false)
      info.directory?.should be_true
      (info.permissions.value & 0o077).should eq 0
      {% if flag?(:unix) %}
        info.owner_id.should eq LibC.getuid.to_s
      {% end %}
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
