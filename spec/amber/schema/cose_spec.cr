require "../../spec_helper"

describe Amber::Schema::COSE do
  key = Bytes.new(32) { |index| (index + 1).to_u8 }
  provider = Amber::Schema::COSE::KeyProvider.new(key, "primary")
  data = {
    "name"  => JSON::Any.new("Amber"),
    "count" => JSON::Any.new(2_i64),
  }

  it "round-trips authenticated CBOR in a tagged COSE Encrypt0 message" do
    plaintext = Amber::Schema::CBOR.encode(data)
    encrypted = Amber::Schema::COSE.encrypt0(plaintext, provider)
    encrypted[0].should eq(0xd0_u8)

    opened = Amber::Schema::COSE.decrypt0(IO::Memory.new(encrypted), provider)
    Amber::Schema::CBOR.decode_object(IO::Memory.new(opened)).should eq(data)
  end

  it "uses a fresh nonce for every message" do
    plaintext = Amber::Schema::CBOR.encode(data)
    Amber::Schema::COSE.encrypt0(plaintext, provider).should_not eq(
      Amber::Schema::COSE.encrypt0(plaintext, provider)
    )
  end

  it "rejects ciphertext tampering without exposing a crypto oracle" do
    encrypted = Amber::Schema::COSE.encrypt0(Amber::Schema::CBOR.encode(data), provider)
    encrypted[encrypted.size - 1] ^= 1_u8
    expect_raises(Amber::Schema::COSE::Error, "Encrypted request authentication failed") do
      Amber::Schema::COSE.decrypt0(IO::Memory.new(encrypted), provider)
    end
  end

  it "supports key rotation by key id" do
    old_key = Bytes.new(32, 9_u8)
    old_provider = Amber::Schema::COSE::KeyProvider.new(old_key, "old")
    encrypted = Amber::Schema::COSE.encrypt0(Amber::Schema::CBOR.encode(data), old_provider)

    rotated = Amber::Schema::COSE::KeyProvider.new(key, "new").add("old", old_key)
    Amber::Schema::COSE.decrypt0(IO::Memory.new(encrypted), rotated).should_not be_empty
  end

  it "isolates nonce and cipher state across concurrent messages" do
    channel = Channel(Tuple(Bytes, Bytes)).new
    payload = Amber::Schema::CBOR.encode(data)

    50.times do
      spawn do
        encrypted = Amber::Schema::COSE.encrypt0(payload, provider)
        opened = Amber::Schema::COSE.decrypt0(IO::Memory.new(encrypted), provider)
        channel.send({encrypted, opened})
      end
    end

    ciphertexts = Set(String).new
    50.times do
      encrypted, opened = channel.receive
      decoded = Amber::Schema::CBOR.decode_object(IO::Memory.new(opened))
      decoded.should eq(data)
      ciphertexts << encrypted.hexstring
    end
    ciphertexts.size.should eq(50)
  end
end

describe Amber::Schema::COSE::ChaCha20Poly1305 do
  it "reproduces the RFC 8439 section 2.8.2 vector" do
    key = "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f".hexbytes
    nonce = "070000004041424344454647".hexbytes
    aad = "50515253c0c1c2c3c4c5c6c7".hexbytes
    plaintext = "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".to_slice
    expected = "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6" \
               "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36" \
               "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc" \
               "3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691"

    sealed = Amber::Schema::COSE::ChaCha20Poly1305.seal(key, nonce, plaintext, aad)
    sealed.hexstring.should eq(expected)
    Amber::Schema::COSE::ChaCha20Poly1305.open(key, nonce, sealed, aad).should eq(plaintext)
  end
end
