require "../../../spec_helper"

# Every hostile case must be rejected while allocating far less than this.
private MAX_REJECTION_BYTES = 8_u64 * 1024 * 1024

module Amber::Router::Parsers
  describe ParamBudget do
    describe "#reserve_array_slot!" do
      it "pads a short gap and returns the index" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)
        list_of_items = [] of ::JSON::Any

        budget.reserve_array_slot!(list_of_items, "2").should eq 2
        list_of_items.size.should eq 3
        budget.padding_used.should eq 2
      end

      it "rejects an index above max_array_index without allocating for it" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)
        list_of_items = [] of ::JSON::Any

        allocated = bytes_allocated_by do
          error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
            budget.reserve_array_slot!(list_of_items, "999999999")
          end
          error.status_code.should eq 400
          error.limit_name.should eq "max_array_index"
        end

        list_of_items.should be_empty
        allocated.should be < MAX_REJECTION_BYTES
      end

      it "rejects an index that overflows Int64 with a 400 instead of OverflowError" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)

        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          budget.reserve_array_slot!([] of ::JSON::Any, "99999999999999999999999")
        end
        error.status_code.should eq 400
      end

      it "rejects an index too far past the end of the array" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_array_index_gap = 4
        budget = ParamBudget.new(config)

        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          budget.reserve_array_slot!([] of ::JSON::Any, "5")
        end
        error.limit_name.should eq "max_array_index_gap"
      end

      it "rejects padding beyond max_array_padding across one request" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_array_padding = 50
        budget = ParamBudget.new(config)

        budget.reserve_array_slot!([] of ::JSON::Any, "30")
        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          budget.reserve_array_slot!([] of ::JSON::Any, "30")
        end
        error.limit_name.should eq "max_array_padding"
      end
    end

    describe "#admit!" do
      it "rejects more parameters than max_params" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_params = 2
        budget = ParamBudget.new(config)

        budget.admit!("a", "1")
        budget.admit!("b", "2")
        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          budget.admit!("c", "3")
        end
        error.limit_name.should eq "max_params"
      end

      it "rejects an oversized key or value" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_key_bytes = 8
        config.max_value_bytes = 8
        budget = ParamBudget.new(config)

        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_key_bytes/) do
          budget.admit!("k" * 9, "v")
        end
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
          budget.admit!("k", "v" * 9)
        end
      end

      it "rejects a key nested deeper than max_nesting_depth" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)

        error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
          budget.admit!("a#{"[b]" * 40}", "x")
        end
        error.limit_name.should eq "max_nesting_depth"
      end

      it "admits bracketed record ids, which are checked only where an array slot is reserved" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)

        ["users[1000001][name]", "items[999999999]", "items[99999999999999999999]"].each do |key|
          budget.admit!(key, "x")
        end
        budget.param_count.should eq 3
      end

      it "admits ordinary keys" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)

        ["title", "user[name]", "items[0]", "items[100][name]", "tags[]", "user.address.city", "a[-]", "price[-1.5]"].each do |key|
          budget.admit!(key, "x")
        end
        budget.param_count.should eq 8
      end
    end

    describe "#read_bounded" do
      it "rejects the first byte past the limit" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)

        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
          budget.read_bounded(IO::Memory.new("x" * 11), 10, "max_form_body_bytes")
        end
        budget.read_bounded(IO::Memory.new("x" * 10), 10, "max_form_body_bytes").should eq "x" * 10
      end

      it "keeps no more than the limit when a large value runs one byte over" do
        limit = 4 * 1_048_576
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)
        body = "x" * (limit + 1)

        allocated = bytes_allocated_by do
          expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
            budget.read_bounded(IO::Memory.new(body), limit, "max_value_bytes")
          end
        end
        # Growing an in-memory buffer past the limit would cost at least
        # four times the limit in total; reading by blocks stays near two.
        allocated.should be < (limit * 5 // 2).to_u64
      end
    end
  end

  describe FormData do
    it "rejects a body with more fields than max_params" do
      config = Amber::Configuration::ParamsConfig.new
      body = (0..config.max_params).map { |i| "f#{i}=x" }.join("&")
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body)

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
          FormData.parse(request, ParamBudget.new(config))
        end
      end
      allocated.should be < MAX_REJECTION_BYTES
    end

    it "rejects a body larger than max_form_body_bytes" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_form_body_bytes = 64
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a=" + "x" * 100)

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
        FormData.parse(request, ParamBudget.new(config))
      end
    end
  end

  describe Multipart do
    it "rejects a field value larger than max_value_bytes" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_value_bytes = 16
      boundary = "AmberLimitBoundary"
      body = "--#{boundary}\r\nContent-Disposition: form-data; name=\"note\"\r\n\r\n#{"x" * 64}\r\n--#{boundary}--\r\n"
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_value_bytes/) do
        Multipart.parse(request, ParamBudget.new(config))
      end
    end
  end
end

private def multipart_request(boundary : String, list_of_parts : Array(Tuple(String, String?, String))) : HTTP::Request
  body = String.build do |io|
    list_of_parts.each do |name, filename, content|
      io << "--" << boundary << "\r\n"
      io << %(Content-Disposition: form-data; name="#{name}")
      io << %(; filename="#{filename}") if filename
      io << "\r\n\r\n" << content << "\r\n"
    end
    io << "--" << boundary << "--\r\n"
  end
  HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"}, body)
end

private def form_request(body : String) : HTTP::Request
  HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, body)
end

module Amber::Router::Parsers
  describe FormData do
    context "at the 8 MiB body boundary" do
      it "rejects a body of a million empty pairs after max_params pairs, without holding the body" do
        config = Amber::Configuration::ParamsConfig.new
        request = form_request("a=&" * 2_800_000)

        allocated = bytes_allocated_by do
          expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
            FormData.parse(request, ParamBudget.new(config))
          end
        end
        allocated.should be < MAX_REJECTION_BYTES
      end

      it "rejects the first byte past max_form_body_bytes with allocation bounded by the cap" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_params = 1_000_000
        value = "x" * 9_000
        pair_count = config.max_form_body_bytes // (value.bytesize + 4) + 1
        request = form_request(Array.new(pair_count, "f=#{value}").join("&"))

        allocated = bytes_allocated_by do
          expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
            FormData.parse(request, ParamBudget.new(config))
          end
        end
        # Total bytes handed out, garbage included: each admitted pair is read,
        # decoded, and stored once, so the total stays a small multiple of the
        # cap no matter how large the body is.
        allocated.should be < 8_u64 * config.max_form_body_bytes
      end

      it "accepts a body of exactly max_form_body_bytes and rejects one byte more" do
        config = Amber::Configuration::ParamsConfig.new
        config.max_form_body_bytes = 100

        FormData.parse(form_request("a=" + "x" * 98), ParamBudget.new(config))["a"].bytesize.should eq 98
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
          FormData.parse(form_request("a=" + "x" * 99), ParamBudget.new(config))
        end
      end
    end

    it "checks both parse_part overloads pair by pair" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_params = 1

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        FormData.parse_part(IO::Memory.new("a=1&b=2"), config)
      end
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        FormData.parse_part("a=1&b=2", config)
      end
    end
  end

  describe Multipart do
    it "rejects a body past max_multipart_body_bytes while it streams" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_multipart_body_bytes = 1_024
      request = multipart_request("AmberLimitBoundary", [
        {"first", "a.txt", "x" * 600},
        {"second", "b.txt", "x" * 600},
      ])

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_multipart_body_bytes/) do
        Multipart.parse(request, ParamBudget.new(config))
      end
    end

    it "rejects a file past max_file_bytes without holding it in memory" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_file_bytes = 1_048_576_i64
      request = multipart_request("AmberLimitBoundary", [{"upload", "big.bin", "x" * 20_000_000}])

      allocated = bytes_allocated_by do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_file_bytes/) do
          Multipart.parse(request, ParamBudget.new(config))
        end
      end
      allocated.should be < MAX_REJECTION_BYTES
    end

    it "counts files and fields together toward max_params" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_params = 2
      request = multipart_request("AmberLimitBoundary", [
        {"note", nil, "x"},
        {"upload", "a.txt", "x"},
        {"other", nil, "x"},
      ])

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        Multipart.parse(request, ParamBudget.new(config))
      end
    end
  end

  describe Amber::Router::Params do
    it "checks ordinary query access against max_params" do
      query = (0..1_000).map { "a=1" }.join("&")
      params = Amber::Router::Params.new(HTTP::Request.new("GET", "/?#{query}"))

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_params/) do
        params.fetch_all("a")
      end
    end

    it "rejects a deeply nested key on ordinary query access" do
      params = Amber::Router::Params.new(HTTP::Request.new("GET", "/?a#{"[b]" * 40}=x"))
      error = expect_raises(Amber::Exceptions::ParameterLimitExceeded) do
        params["a"]?
      end
      error.limit_name.should eq "max_nesting_depth"
    end

    it "reads a field named by a large record id as an ordinary parameter" do
      params = Amber::Router::Params.new(HTTP::Request.new("GET", "/?users[1000001][name]=Ada"))
      params["users[1000001][name]"]?.should eq "Ada"
    end

    it "still rejects that record id where a schema parser would reserve array slots for it" do
      request = HTTP::Request.new("GET", "/?items[1000001]=x")
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_array_index/) do
        Amber::Schema::Parser::QueryParser.parse_query_string(request.query.to_s)
      end
    end

    it "rejects a deeply nested key in a form, and admits a large record id in a multipart body" do
      key = "a#{"[b]" * 40}"
      form_request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "#{key}=x")
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_nesting_depth/) do
        Amber::Router::Params.new(form_request).form_params
      end

      boundary = "AdmissionBoundary"
      multipart_request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"},
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"items[999999999]\"\r\n\r\nx\r\n--#{boundary}--\r\n")
      Amber::Router::Params.new(multipart_request).multipart_params["items[999999999]"]?.should eq "x"
    end

    it "reads a form by its media type, compared without regard to letter case" do
      mixed_case = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "Application/X-Www-Form-Urlencoded; charset=UTF-8"}, "title=hello")
      mixed_case.form_params["title"]?.should eq "hello"
      mixed_case.params.form_params["title"]?.should eq "hello"

      other_type = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencodedx"}, "title=hello")
      other_type.form_params?.should be_nil
      other_type.params.form_params.size.should eq 0

      boundary = "MediaTypeBoundary"
      multipart = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "Multipart/Form-Data; boundary=#{boundary}"},
        "--#{boundary}\r\nContent-Disposition: form-data; name=\"title\"\r\n\r\nhello\r\n--#{boundary}--\r\n")
      Amber::Router::Params.new(multipart).multipart_params["title"]?.should eq "hello"
    end

    it "raises a body rejection again on every later read" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_form_body_bytes = 8
      request = HTTP::Request.new("PUT", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "123456789&x=y")
      request.param_budget = ParamBudget.new(config)

      2.times do
        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
          request.form_params
        end
      end
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
        request.params.form_params
      end
    end

    it "keeps ordinary query access working within the limits" do
      params = Amber::Router::Params.new(HTTP::Request.new("GET", "/?a=1&a=2"))
      params.fetch_all("a").should eq ["1", "2"]
    end
  end

  describe "extreme configuration values" do
    it "returns limit errors, never overflow, with every limit at its type maximum" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_array_index = Int32::MAX
      config.max_array_index_gap = Int32::MAX
      config.max_array_padding = Int32::MAX
      config.max_params = Int32::MAX
      config.max_nesting_depth = Int32::MAX
      config.max_key_bytes = Int32::MAX
      config.max_value_bytes = Int32::MAX
      config.max_form_body_bytes = Int32::MAX
      config.max_multipart_body_bytes = Int64::MAX
      config.max_file_bytes = Int64::MAX

      result = Amber::Schema::Parser::QueryParser.parse_query_string("items[0]=a&items[1]=b", config)
      result["items"].as_a.map(&.as_s).should eq ["a", "b"]

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /array indices/) do
        Amber::Schema::Parser::QueryParser.parse_query_string("items[99999999999]=x", config)
      end
      FormData.parse_part("a=1", config)["a"].should eq "1"
    end

    it "returns a limit error with the gap and padding limits at zero" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_array_index_gap = 0
      config.max_array_padding = 0
      budget = ParamBudget.new(config)
      list_of_items = [] of ::JSON::Any

      budget.reserve_array_slot!(list_of_items, "0").should eq 0
      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_array_index_gap/) do
        budget.reserve_array_slot!(list_of_items, "2")
      end
    end
  end
end
