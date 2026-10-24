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
    end

    describe "#read_bounded" do
      it "stops reading one byte past the limit" do
        budget = ParamBudget.new(Amber::Configuration::ParamsConfig.new)
        io = IO::Memory.new("x" * 100)

        expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
          budget.read_bounded(io, 10, "max_form_body_bytes")
        end
        io.pos.should eq 11
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
