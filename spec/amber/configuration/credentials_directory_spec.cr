require "../../spec_helper"
require "file_utils"

private FIXTURE_CREDENTIALS_DIRECTORY = File.expand_path("./spec/support/credentials/app_service")

struct SpecAppCredentials
  include YAML::Serializable

  property secret_key_base : String = ""
  property database_url : String? = nil
  property smtp_password : String? = nil

  @[YAML::Field(key: "multiline_note")]
  property note : String = ""

  def initialize
  end
end

struct SpecPortCredentials
  include YAML::Serializable

  property port : Int32 = 0

  def initialize
  end
end

struct SpecRequiredCredentials
  include YAML::Serializable

  property signing_key : String

  def initialize(@signing_key : String)
  end
end

# Builds a throwaway credentials directory and an "outside" directory
# beside it, yields both, and removes them afterwards.
private def with_scratch_directories(&)
  scratch = File.join(Dir.tempdir, "amber-credentials-spec-#{Random::Secure.hex(8)}")
  credentials = File.join(scratch, "credentials")
  outside = File.join(scratch, "outside")
  Dir.mkdir_p(credentials)
  Dir.mkdir_p(outside)
  begin
    yield credentials, outside
  ensure
    FileUtils.rm_rf(scratch)
  end
end

module Amber::Configuration
  describe CredentialsDirectory do
    describe "#read" do
      it "reads one entry per file, keyed by file name, contents byte for byte" do
        credentials = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read

        credentials.keys.should eq ["database_url", "multiline_note", "secret_key_base", "smtp_password"]
        credentials["secret_key_base"].should eq "fixture-secret-key-base-0123456789abcdef0123456789"
        credentials["database_url"].should eq "postgres://fixture:fixture@localhost/fixture_app"
        credentials["multiline_note"].should eq "line one\nline two\n"
      end

      it "follows a symlink whose target stays inside the directory" do
        with_scratch_directories do |credentials, _outside|
          File.write(File.join(credentials, "real_key"), "inside")
          File.symlink(File.join(credentials, "real_key"), File.join(credentials, "linked_key"))

          CredentialsDirectory.new(credentials).read["linked_key"].should eq "inside"
        end
      end

      it "raises CredentialsDirectoryNotFound for a missing directory" do
        expect_raises(Amber::Exceptions::CredentialsDirectoryNotFound, /not found/) do
          CredentialsDirectory.new("./spec/support/credentials/no_such_service").read
        end
      end

      it "raises CredentialsDirectoryNotFound when the path is a file" do
        expect_raises(Amber::Exceptions::CredentialsDirectoryNotFound) do
          CredentialsDirectory.new(File.join(FIXTURE_CREDENTIALS_DIRECTORY, "secret_key_base")).read
        end
      end

      it "raises CredentialSymlinkOutsideDirectory for a link that leaves the directory" do
        with_scratch_directories do |credentials, outside|
          File.write(File.join(outside, "stolen"), "outside-value")
          File.symlink(File.join(outside, "stolen"), File.join(credentials, "api_key"))

          error = expect_raises(Amber::Exceptions::CredentialSymlinkOutsideDirectory) do
            CredentialsDirectory.new(credentials).read
          end
          error.message.to_s.should contain "api_key"
          error.message.to_s.should_not contain "outside-value"
        end
      end

      it "raises CredentialSymlinkOutsideDirectory for a relative link that climbs out" do
        with_scratch_directories do |credentials, outside|
          File.write(File.join(outside, "stolen"), "outside-value")
          File.symlink("../outside/stolen", File.join(credentials, "api_key"))

          expect_raises(Amber::Exceptions::CredentialSymlinkOutsideDirectory) do
            CredentialsDirectory.new(credentials).read
          end
        end
      end

      it "raises CredentialNotARegularFile for a subdirectory" do
        with_scratch_directories do |credentials, _outside|
          Dir.mkdir(File.join(credentials, "nested"))

          expect_raises(Amber::Exceptions::CredentialNotARegularFile, /nested/) do
            CredentialsDirectory.new(credentials).read
          end
        end
      end

      it "raises CredentialUnreadable for a file the process may not read" do
        with_scratch_directories do |credentials, _outside|
          locked = File.join(credentials, "locked_key")
          File.write(locked, "locked-value")
          File.chmod(locked, 0o000)

          # Root reads any file, so the check only means something for other users.
          if File::Info.readable?(locked)
            pending!("running as a user that can read mode 000 files")
          end

          begin
            error = expect_raises(Amber::Exceptions::CredentialUnreadable) do
              CredentialsDirectory.new(credentials).read
            end
            error.message.to_s.should contain "locked_key"
            error.message.to_s.should_not contain "locked-value"
          ensure
            File.chmod(locked, 0o600)
          end
        end
      end

      it "raises CredentialTooLarge for a file over the size cap" do
        with_scratch_directories do |credentials, _outside|
          File.write(File.join(credentials, "big_key"), "x" * 17)

          error = expect_raises(Amber::Exceptions::CredentialTooLarge) do
            CredentialsDirectory.new(credentials, maximum_file_size: 16_i64).read
          end
          error.message.to_s.should contain "16-byte cap"
          error.message.to_s.should_not contain "x" * 17
        end
      end

      it "accepts a file exactly at the size cap" do
        with_scratch_directories do |credentials, _outside|
          File.write(File.join(credentials, "edge_key"), "y" * 16)

          CredentialsDirectory.new(credentials, maximum_file_size: 16_i64).read["edge_key"].should eq "y" * 16
        end
      end

      it "reads an empty directory as no credentials" do
        with_scratch_directories do |credentials, _outside|
          CredentialsDirectory.new(credentials).read.should be_empty
        end
      end
    end

    describe "#read_credential" do
      it "reads one credential by name" do
        CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY)
          .read_credential("database_url")
          .should eq "postgres://fixture:fixture@localhost/fixture_app"
      end

      it "raises CredentialPathTraversal for names that leave the directory" do
        directory = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY)
        ["../app_service/secret_key_base", "..", ".", "", "nested/key", "/etc/passwd", "key\0", "k" * 256].each do |name|
          expect_raises(Amber::Exceptions::CredentialPathTraversal) do
            directory.read_credential(name)
          end
        end
      end

      it "raises CredentialNotFound for a name with no file" do
        expect_raises(Amber::Exceptions::CredentialNotFound, /missing_key/) do
          CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_credential("missing_key")
        end
      end

      it "raises CredentialNotFound for a dangling symlink" do
        with_scratch_directories do |credentials, _outside|
          File.symlink(File.join(credentials, "gone"), File.join(credentials, "dangling_key"))

          expect_raises(Amber::Exceptions::CredentialNotFound) do
            CredentialsDirectory.new(credentials).read_credential("dangling_key")
          end
        end
      end
    end

    describe "#read_into" do
      it "builds the typed section, honoring YAML key renames" do
        credentials = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_into(SpecAppCredentials)

        credentials.secret_key_base.should eq "fixture-secret-key-base-0123456789abcdef0123456789"
        credentials.database_url.should eq "postgres://fixture:fixture@localhost/fixture_app"
        credentials.note.should eq "line one\nline two\n"
      end

      it "keeps a credential whose contents read as YAML null as that text" do
        credentials = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_into(SpecAppCredentials)

        credentials.smtp_password.should eq "null"
      end

      it "keeps the default for a field with no file" do
        with_scratch_directories do |credentials, _outside|
          File.write(File.join(credentials, "secret_key_base"), "only-this-one")

          section = CredentialsDirectory.new(credentials).read_into(SpecAppCredentials)
          section.secret_key_base.should eq "only-this-one"
          section.database_url.should be_nil
        end
      end

      it "raises CredentialsDoNotFitSection without quoting the value" do
        with_scratch_directories do |credentials, _outside|
          File.write(File.join(credentials, "port"), "not-a-port-secret")

          error = expect_raises(Amber::Exceptions::CredentialsDoNotFitSection, /SpecPortCredentials/) do
            CredentialsDirectory.new(credentials).read_into(SpecPortCredentials)
          end
          error.message.to_s.should_not contain "not-a-port-secret"
        end
      end

      it "raises CredentialsDoNotFitSection when a required field has no file" do
        with_scratch_directories do |credentials, _outside|
          expect_raises(Amber::Exceptions::CredentialsDoNotFitSection) do
            CredentialsDirectory.new(credentials).read_into(SpecRequiredCredentials)
          end
        end
      end
    end
  end

  describe ".register_credentials" do
    it "raises CredentialsRegisteredAfterSettingsLoad once Amber.settings is loaded" do
      # spec_helper loads Amber.settings before any spec runs.
      Amber.settings_loaded?.should be_true

      expect_raises(Amber::Exceptions::CredentialsRegisteredAfterSettingsLoad, /spec_late_credentials/) do
        Amber::Configuration.register_credentials(:spec_late_credentials, SpecAppCredentials, FIXTURE_CREDENTIALS_DIRECTORY)
      end
      Amber::Configuration.custom_config_defaults.has_key?("spec_late_credentials").should be_false
    end
  end

  describe "a registered credentials section" do
    it "reaches typed settings through the loader" do
      section = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_into(SpecAppCredentials)
      Amber::Configuration.store_credentials_section("spec_loaded_credentials", section)

      settings = Amber::Environment::Loader.new(:v2_minimal, "./spec/support/config/").settings
      credentials = settings.custom(:spec_loaded_credentials, SpecAppCredentials)
      credentials.secret_key_base.should eq "fixture-secret-key-base-0123456789abcdef0123456789"
      credentials.database_url.should eq "postgres://fixture:fixture@localhost/fixture_app"
    end

    it "takes an AMBER_ override over the credential file" do
      section = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_into(SpecAppCredentials)
      Amber::Configuration.store_credentials_section("spec_overridden_credentials", section)

      ENV["AMBER_SPEC_OVERRIDDEN_CREDENTIALS_DATABASE_URL"] = "postgres://override/db"
      begin
        settings = Amber::Environment::Loader.new(:v2_minimal, "./spec/support/config/").settings
        credentials = settings.custom(:spec_overridden_credentials, SpecAppCredentials)
        credentials.database_url.should eq "postgres://override/db"
        credentials.secret_key_base.should eq "fixture-secret-key-base-0123456789abcdef0123456789"
      ensure
        ENV.delete("AMBER_SPEC_OVERRIDDEN_CREDENTIALS_DATABASE_URL")
      end
    end

    it "is rejected when the YAML file defines the same section" do
      section = CredentialsDirectory.new(FIXTURE_CREDENTIALS_DIRECTORY).read_into(SpecAppCredentials)
      Amber::Configuration.store_credentials_section("spec_yaml_conflict_credentials", section)

      error = expect_raises(Amber::Exceptions::ConfigurationError, /spec_yaml_conflict_credentials is loaded from the credentials directory/) do
        Amber::Environment::Loader.new(:v2_with_credentials_section, "./spec/support/config/").settings
      end
      error.message.to_s.should_not contain "from-yaml"
    end
  end
end
