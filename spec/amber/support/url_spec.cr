require "../../../spec_helper"

module Amber::Support
  describe URL do
    describe "#to_s" do

      context "with all options" do
        it "generates a a full url" do
          options = {
            protocol: "https",
            host: "www.ambercr.io",
            port: 443,
            anchor: "awesome",
            query_string: "stock=APPL&market=dow",
            path: "/users/1",
            only_path: false,
            end_slash: true,
          }
          url = URL.new(**options)

          url.to_s.should eq "https://www.ambercr.io/users/1/?stock=APPL&market=dow#awesome"
        end
      end

      context "when only path is true" do
        it "generates path" do
          path = "/some/path"
          url = URL.new(only_path: true, path: path)

          url.to_s.should eq path
        end

        it "it generates root path" do
          url = URL.new(only_path: true, end_slash: true)

          url.to_s.should eq "/"
        end
      end

      context "when only path is false" do
        it "builds url for host 127.0.0.1" do
          options = {only_path: false, host: "127.0.0.1"}
          url = URL.new(**options)

          url.to_s.should eq "http://127.0.0.1"
        end

        it "builds url with system default host" do
          options = {only_path: false}
          url = URL.new(**options)

          url.to_s.should eq "http://#{Crystal::System.hostname}"
        end

        context "when port is provided" do
          it "does not append port for http" do
            options = {only_path: false, port: 80}
            url = URL.new(**options)

            url.to_s.should eq "http://#{Crystal::System.hostname}"
          end

          it "does not append port for https" do
            options = {only_path: false, protocol: "https", port: 443}
            url = URL.new(**options)

            url.to_s.should eq "https://#{Crystal::System.hostname}"
          end

          it "appends port for other than port 80 and 443" do
            options = {only_path: false, protocol: "https", port: 3000}
            url = URL.new(**options)

            url.to_s.should eq "https://#{Crystal::System.hostname}:3000"
          end
        end

        context "when query string is provided" do
          context "when only path is true" do
            it "appends URL encoded query string" do
              query = HTTP::Params.parse("hello=world").to_s
              options = {only_path: true, query_string: query}
              url = URL.new(**options)

              url.to_s.should eq "?#{query}"
            end

            it "does not append the query string" do
              query_string = ""
              options = {only_path: true, query_string: query_string, end_slash: true}
              url = URL.new(**options)
              url.to_s.should eq "/"
            end

            it "returns root path for empty query string" do
              options = {only_path: true, query_string: "", end_slash: true}
              url = URL.new(**options)
              url.to_s.should eq "/"
            end
          end

          context "when only path is false" do
            it "appends query string to url with host" do
              query_string = HTTP::Params.parse("hello=world").to_s
              options = {only_path: false, query_string: query_string}
              url = URL.new(**options)

              url.to_s.should eq "http://#{Crystal::System.hostname}?#{query_string.to_s}"
            end

            it "does not append query string when nil" do
              options = {only_path: false, query_string: ""}
              url = URL.new(**options)
              url.to_s.should eq "http://#{Crystal::System.hostname}"
            end

            it "does not append query string when nil" do
              options = {only_path: false, query_string: ""}
              url = URL.new(**options)
              url.to_s.should eq "http://#{Crystal::System.hostname}"
            end
          end

          context "with anchor" do
            it "appends anchor when present" do
              options = {only_path: false, anchor: "hello"}
              url = URL.new(**options)
              url.to_s.should eq "http://#{Crystal::System.hostname}#hello"
            end

            it "does not append anchor when blank" do
              options = {only_path: false, anchor: ""}
              url = URL.new(**options)
              url.to_s.should eq "http://#{Crystal::System.hostname}"
            end
          end
        end
      end
    end
  end
end
