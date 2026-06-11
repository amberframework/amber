require "../../../spec_helper"

module Amber::Controller::Helpers
  describe NumberHelpers do
    controller = build_controller

    describe "#number_with_delimiter" do
      it "formats a large integer with commas" do
        controller.number_with_delimiter(1234567).should eq "1,234,567"
      end

      it "does not add delimiter to small numbers" do
        controller.number_with_delimiter(123).should eq "123"
      end

      it "handles zero" do
        controller.number_with_delimiter(0).should eq "0"
      end

      it "handles negative numbers" do
        controller.number_with_delimiter(-1234567).should eq "-1,234,567"
      end

      it "handles float numbers" do
        controller.number_with_delimiter(1234567.89).should eq "1,234,567.89"
      end

      it "uses a custom delimiter" do
        controller.number_with_delimiter(1234567, delimiter: ".").should eq "1.234.567"
      end

      it "handles exactly 1000" do
        controller.number_with_delimiter(1000).should eq "1,000"
      end
    end

    describe "#number_to_currency" do
      it "formats a number as currency with default dollar sign" do
        controller.number_to_currency(1234.5).should eq "$1,234.50"
      end

      it "uses a custom unit" do
        controller.number_to_currency(1234.5, unit: "EUR").should eq "EUR1,234.50"
      end

      it "uses custom precision" do
        controller.number_to_currency(1234.567, precision: 3).should eq "$1,234.567"
      end

      it "handles zero" do
        controller.number_to_currency(0).should eq "$0.00"
      end

      it "handles negative amounts" do
        controller.number_to_currency(-99.99).should eq "-$99.99"
      end

      it "formats large amounts" do
        controller.number_to_currency(1000000).should eq "$1,000,000.00"
      end

      it "handles precision of 0" do
        controller.number_to_currency(1234.56, precision: 0).should eq "$1,235"
      end
    end

    describe "#number_to_percentage" do
      it "formats a number as a percentage" do
        controller.number_to_percentage(75.5).should eq "75.5%"
      end

      it "uses custom precision" do
        controller.number_to_percentage(75.567, precision: 2).should eq "75.57%"
      end

      it "handles zero" do
        controller.number_to_percentage(0).should eq "0.0%"
      end

      it "handles 100 percent" do
        controller.number_to_percentage(100).should eq "100.0%"
      end

      it "handles precision of 0" do
        controller.number_to_percentage(75.5, precision: 0).should eq "76%"
      end
    end

    describe "#number_to_human_size" do
      it "formats bytes" do
        controller.number_to_human_size(500).should eq "500 Bytes"
      end

      it "formats kilobytes" do
        controller.number_to_human_size(1024).should eq "1.00 KB"
      end

      it "formats megabytes" do
        controller.number_to_human_size(1048576).should eq "1.00 MB"
      end

      it "formats gigabytes" do
        controller.number_to_human_size(1073741824).should eq "1.00 GB"
      end

      it "formats terabytes" do
        controller.number_to_human_size(1099511627776).should eq "1.00 TB"
      end

      it "handles zero" do
        controller.number_to_human_size(0).should eq "0 Bytes"
      end

      it "formats fractional sizes" do
        controller.number_to_human_size(1536).should eq "1.50 KB"
      end

      it "handles 1 byte" do
        controller.number_to_human_size(1).should eq "1 Bytes"
      end
    end
  end
end
