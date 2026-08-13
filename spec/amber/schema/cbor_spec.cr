require "../../spec_helper"

describe Amber::Schema::CBOR do
  it "round-trips deterministic schema objects" do
    data = {
      "name"   => JSON::Any.new("Amber"),
      "count"  => JSON::Any.new(2_i64),
      "active" => JSON::Any.new(true),
      "tags"   => JSON::Any.new([JSON::Any.new("web"), JSON::Any.new("native")]),
    }

    encoded = Amber::Schema::CBOR.encode(data)
    Amber::Schema::CBOR.decode_object(IO::Memory.new(encoded)).should eq(data)
    Amber::Schema::CBOR.encode(data).should eq(encoded)
  end

  it "rejects duplicate map keys" do
    bytes = Bytes[0xa2, 0x61, 0x61, 0x01, 0x61, 0x61, 0x02]
    expect_raises(Amber::Schema::CBOR::DecodeError, /duplicate map key/) do
      Amber::Schema::CBOR.decode_object(IO::Memory.new(bytes))
    end
  end

  it "rejects indefinite-length documents" do
    expect_raises(Amber::Schema::CBOR::DecodeError, /indefinite-length/) do
      Amber::Schema::CBOR.decode_object(IO::Memory.new(Bytes[0xbf, 0xff]))
    end
  end

  it "rejects trailing data" do
    expect_raises(Amber::Schema::CBOR::DecodeError, /trailing bytes/) do
      Amber::Schema::CBOR.decode_object(IO::Memory.new(Bytes[0xa0, 0x00]))
    end
  end
end
