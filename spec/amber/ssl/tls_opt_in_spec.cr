require "file_utils"
require "../../spec_helper"

# Runs the block with `server.ssl` and the mailer settings as given, and puts
# the previous values back afterward.
private def with_tls_settings(ssl_files : String?, mailer_adapter : String = "memory", smtp_use_tls : Bool = true, &)
  settings = Amber.settings
  mailer = settings.mailer
  original_key_file = settings.ssl_key_file
  original_cert_file = settings.ssl_cert_file
  original_adapter = mailer.adapter
  original_use_tls = mailer.smtp.use_tls
  begin
    settings.ssl_key_file = ssl_files
    settings.ssl_cert_file = ssl_files
    mailer.adapter = mailer_adapter
    mailer.smtp.use_tls = smtp_use_tls
    yield
  ensure
    settings.ssl_key_file = original_key_file
    settings.ssl_cert_file = original_cert_file
    mailer.adapter = original_adapter
    mailer.smtp.use_tls = original_use_tls
  end
end

# Compiles spec/fixtures/tls/https_app.cr, which requires "amber/tls", with
# the given flags and runs it: it serves HTTPS through Amber::TLS::Backend
# with a chain spec/fixtures/tls/make_spec_chain.sh makes, fetches its own page over TLS 1.3, and delivers mail
# over STARTTLS and implicit TLS to spec mail servers.
module HTTPSAppProbe
  FIXTURE_DIRECTORY = File.expand_path("../../fixtures/tls", __DIR__)

  record Outcome, status : Process::Status, output : String do
    def value_for(key : String) : String?
      output.each_line do |line|
        line_key, separator, value = line.partition('=')
        return value if separator == "=" && line_key == key
      end
    end
  end

  @@outcome_by_flags = {} of String => Outcome

  def self.outcome(flags : String = "") : Outcome
    @@outcome_by_flags[flags] ||= build_and_run(flags)
  end

  private def self.build_and_run(flags : String) : Outcome
    work_directory = File.tempname("amber-https-app")
    Dir.mkdir_p(work_directory)
    binary = File.join(work_directory, "https_app")
    source = File.join(FIXTURE_DIRECTORY, "https_app.cr")

    build_output = IO::Memory.new
    arguments = ["build", "--no-debug", source, "-o", binary]
    arguments << flags unless flags.empty?
    build = Process.run(FixtureCompiler.executable, arguments, output: build_output, error: build_output)
    raise "#{source} did not compile with '#{flags}':\n#{build_output}" unless build.success?

    # A fresh chain for each run, so no private key is committed.
    chain_directory = File.join(work_directory, "chain")
    Dir.mkdir_p(chain_directory)
    chain_output = IO::Memory.new
    made = Process.run("/bin/bash", [File.join(FIXTURE_DIRECTORY, "make_spec_chain.sh"), chain_directory], output: chain_output, error: chain_output)
    raise "make_spec_chain.sh failed:\n#{chain_output}" unless made.success?

    run_output = IO::Memory.new
    status = Process.run(binary, [chain_directory], env: {"AMBER_ENV" => nil}, chdir: work_directory,
      output: run_output, error: run_output)
    Outcome.new(status, run_output.to_s)
  ensure
    FileUtils.rm_rf(work_directory) if work_directory
  end
end

describe "TLS as an opt-in" do
  describe "an app that does not require \"amber/tls\"" do
    it "stops at start when server.ssl is set, naming the require" do
      with_tls_settings(ssl_files: __FILE__) do
        error = expect_raises(Amber::Exceptions::TLSNotCompiledIn, %(require "amber/tls")) do
          Amber::Server.instance.check_listener_settings!
        end
        error.message.to_s.should contain "server.ssl.key_file"
      end
    end

    it "stops at start when the smtp mailer uses STARTTLS, naming the require" do
      with_tls_settings(ssl_files: nil, mailer_adapter: "smtp", smtp_use_tls: true) do
        error = expect_raises(Amber::Exceptions::TLSNotCompiledIn, %(require "amber/tls")) do
          Amber::Server.instance.check_listener_settings!
        end
        error.message.to_s.should contain "STARTTLS"
      end
    end

    it "stops at start when the smtp mailer uses implicit TLS, naming the require" do
      with_tls_settings(ssl_files: nil, mailer_adapter: "smtp", smtp_use_tls: false) do
        Amber.settings.mailer.smtp.use_implicit_tls = true
        begin
          expect_raises(Amber::Exceptions::TLSNotCompiledIn, %(require "amber/tls")) do
            Amber::Server.instance.check_listener_settings!
          end
        ensure
          Amber.settings.mailer.smtp.use_implicit_tls = false
        end
      end
    end

    it "starts with the smtp mailer when use_tls is off" do
      with_tls_settings(ssl_files: nil, mailer_adapter: "smtp", smtp_use_tls: false) do
        Amber::Server.instance.check_listener_settings!
      end
    end

    it "starts without TLS settings" do
      with_tls_settings(ssl_files: nil) do
        Amber::Server.instance.check_listener_settings!
      end
    end

    it "refuses STARTTLS when it delivers over SMTP" do
      server = TCPServer.new("127.0.0.1", 0)
      begin
        spawn(name: "smtp greeting spec server") do
          if client = server.accept?
            client << "220 spec ESMTP\r\n"
            client.flush
            client.gets
            client << "250 spec\r\n"
            client.flush
            client.gets
            client.close
          end
        end

        adapter = Amber::Mailer::SMTPAdapter.new(host: "127.0.0.1", port: server.local_address.port, use_tls: true)
        email = Amber::Mailer::Email.new(to: ["recipient@example.com"], from: "sender@example.com")
        expect_raises(Amber::Exceptions::TLSNotCompiledIn, %(require "amber/tls")) do
          adapter.deliver(email)
        end
      ensure
        server.close
      end
    end
  end

  describe "an app that requires \"amber/tls\"" do
    it "serves HTTPS over TLS 1.3 on Beryl with ALPN http/1.1, after a client whose handshake failed" do
      outcome = HTTPSAppProbe.outcome

      outcome.status.success?.should be_true, outcome.output
      outcome.value_for("compiled_in").should eq "true"
      outcome.value_for("context").should eq "Amber::Beryl::TLS::Context::Server"
      outcome.value_for("tls_version").should eq "TLSv1.3"
      outcome.value_for("alpn").should eq "http/1.1"
      outcome.value_for("status").should eq "200"
      outcome.value_for("body").should eq "served over TLS"
    end

    it "delivers mail over STARTTLS and implicit TLS, verifying the server's chain and name" do
      outcome = HTTPSAppProbe.outcome

      outcome.value_for("starttls").should eq("delivered"), outcome.output
      outcome.value_for("starttls_body_seen").should eq "true"
      outcome.value_for("implicit_tls").should eq("delivered"), outcome.output
      outcome.value_for("implicit_tls_body_seen").should eq "true"
      outcome.value_for("untrusted_root").to_s.should contain "did not verify"
    end

    it "fails delivery to a mail server that offers only TLS 1.2, naming the TLS 1.3 requirement" do
      outcome = HTTPSAppProbe.outcome

      {"tls_1_2_server_hello", "tls_1_2_alert"}.each do |key|
        error = outcome.value_for(key).to_s
        error.should contain(Amber::TLS::TLS_1_3_REQUIREMENT), outcome.output
      end
    end

    it "serves and delivers on Beryl when built with the removed -Duse_openssl" do
      outcome = HTTPSAppProbe.outcome("-Duse_openssl")

      outcome.status.success?.should be_true, outcome.output
      outcome.value_for("context").should eq "Amber::Beryl::TLS::Context::Server"
      outcome.value_for("tls_version").should eq "TLSv1.3"
      outcome.value_for("alpn").should eq "http/1.1"
      outcome.value_for("status").should eq "200"
      outcome.value_for("starttls").should eq("delivered"), outcome.output
      outcome.value_for("implicit_tls").should eq("delivered"), outcome.output
      outcome.value_for("tls_1_2_server_hello").to_s.should contain(Amber::TLS::TLS_1_3_REQUIREMENT)
    end
  end
end
