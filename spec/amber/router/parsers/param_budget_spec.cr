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
          FormData.parse(request, config)
        end
      end
      allocated.should be < MAX_REJECTION_BYTES
    end

    it "rejects a body larger than max_form_body_bytes" do
      config = Amber::Configuration::ParamsConfig.new
      config.max_form_body_bytes = 64
      request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/x-www-form-urlencoded"}, "a=" + "x" * 100)

      expect_raises(Amber::Exceptions::ParameterLimitExceeded, /max_form_body_bytes/) do
        FormData.parse(request, config)
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
        Multipart.parse(request, config)
      end
    end
  end
end
