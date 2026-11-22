require "../../../spec_helper"

# The label table of the WHATWG Encoding Standard, one encoding per line
# (https://encoding.spec.whatwg.org/encodings.json, sha256 078212b3...02ac9e7).
private WHATWG_LABEL_TABLE = <<-TABLE
  UTF-8: unicode-1-1-utf-8 unicode11utf8 unicode20utf8 utf-8 utf8 x-unicode20utf8
  IBM866: 866 cp866 csibm866 ibm866
  ISO-8859-2: csisolatin2 iso-8859-2 iso-ir-101 iso8859-2 iso88592 iso_8859-2 iso_8859-2:1987 l2 latin2
  ISO-8859-3: csisolatin3 iso-8859-3 iso-ir-109 iso8859-3 iso88593 iso_8859-3 iso_8859-3:1988 l3 latin3
  ISO-8859-4: csisolatin4 iso-8859-4 iso-ir-110 iso8859-4 iso88594 iso_8859-4 iso_8859-4:1988 l4 latin4
  ISO-8859-5: csisolatincyrillic cyrillic iso-8859-5 iso-ir-144 iso8859-5 iso88595 iso_8859-5 iso_8859-5:1988
  ISO-8859-6: arabic asmo-708 csiso88596e csiso88596i csisolatinarabic ecma-114 iso-8859-6 iso-8859-6-e iso-8859-6-i iso-ir-127 iso8859-6 iso88596 iso_8859-6 iso_8859-6:1987
  ISO-8859-7: csisolatingreek ecma-118 elot_928 greek greek8 iso-8859-7 iso-ir-126 iso8859-7 iso88597 iso_8859-7 iso_8859-7:1987 sun_eu_greek
  ISO-8859-8: csiso88598e csisolatinhebrew hebrew iso-8859-8 iso-8859-8-e iso-ir-138 iso8859-8 iso88598 iso_8859-8 iso_8859-8:1988 visual
  ISO-8859-8-I: csiso88598i iso-8859-8-i logical
  ISO-8859-10: csisolatin6 iso-8859-10 iso-ir-157 iso8859-10 iso885910 l6 latin6
  ISO-8859-13: iso-8859-13 iso8859-13 iso885913
  ISO-8859-14: iso-8859-14 iso8859-14 iso885914
  ISO-8859-15: csisolatin9 iso-8859-15 iso8859-15 iso885915 iso_8859-15 l9
  ISO-8859-16: iso-8859-16
  KOI8-R: cskoi8r koi koi8 koi8-r koi8_r
  KOI8-U: koi8-ru koi8-u
  macintosh: csmacintosh mac macintosh x-mac-roman
  windows-874: dos-874 iso-8859-11 iso8859-11 iso885911 tis-620 windows-874
  windows-1250: cp1250 windows-1250 x-cp1250
  windows-1251: cp1251 windows-1251 x-cp1251
  windows-1252: ansi_x3.4-1968 ascii cp1252 cp819 csisolatin1 ibm819 iso-8859-1 iso-ir-100 iso8859-1 iso88591 iso_8859-1 iso_8859-1:1987 l1 latin1 us-ascii windows-1252 x-cp1252
  windows-1253: cp1253 windows-1253 x-cp1253
  windows-1254: cp1254 csisolatin5 iso-8859-9 iso-ir-148 iso8859-9 iso88599 iso_8859-9 iso_8859-9:1989 l5 latin5 windows-1254 x-cp1254
  windows-1255: cp1255 windows-1255 x-cp1255
  windows-1256: cp1256 windows-1256 x-cp1256
  windows-1257: cp1257 windows-1257 x-cp1257
  windows-1258: cp1258 windows-1258 x-cp1258
  x-mac-cyrillic: x-mac-cyrillic x-mac-ukrainian
  GBK: chinese csgb2312 csiso58gb231280 gb2312 gb_2312 gb_2312-80 gbk iso-ir-58 x-gbk
  gb18030: gb18030
  Big5: big5 big5-hkscs cn-big5 csbig5 x-x-big5
  EUC-JP: cseucpkdfmtjapanese euc-jp x-euc-jp
  ISO-2022-JP: csiso2022jp iso-2022-jp
  Shift_JIS: csshiftjis ms932 ms_kanji shift-jis shift_jis sjis windows-31j x-sjis
  EUC-KR: cseuckr csksc56011987 euc-kr iso-ir-149 korean ks_c_5601-1987 ks_c_5601-1989 ksc5601 ksc_5601 windows-949
  replacement: csiso2022kr hz-gb-2312 iso-2022-cn iso-2022-cn-ext iso-2022-kr replacement
  UTF-16BE: unicodefffe utf-16be
  UTF-16LE: csunicode iso-10646-ucs-2 ucs-2 unicode unicodefeff utf-16 utf-16le
  x-user-defined: x-user-defined
  TABLE

private LIST_OF_ENCODINGS_WITHOUT_A_DECODER = ["replacement", "x-user-defined", "windows-1258"]

private def whatwg_labels_by_name : Hash(String, Array(String))
  WHATWG_LABEL_TABLE.lines.to_h do |line|
    name, labels = line.strip.split(": ")
    {name, labels.split(' ')}
  end
end

# Records every converter the program opens, as a spy on iconv.
module FormCharsetSpy
  class_getter list_of_opened_converters = [] of String
end

struct Crystal::Iconv
  def initialize(from : String, to : String, invalid : Symbol? = nil)
    FormCharsetSpy.list_of_opened_converters << from
    previous_def
  end
end

class FormCharsetController < Amber::Controller::Base
  class_property action_calls = 0

  def create
    self.class.action_calls += 1
    params["title"]
  end
end

private def form_request(charset : String, body : String | Bytes = "title=x") : HTTP::Request
  HTTP::Request.new("POST", "/form-charset", HTTP::Headers{
    "Content-Type" => %(application/x-www-form-urlencoded; charset="#{charset}"),
    "Accept"       => "application/json",
  }, body)
end

private LIST_OF_REFUSED_CHARSETS = {
  "UTF-7"                    => "UTF-7",
  "an iconv-only name"       => "ISO-2022-CN-EXT",
  "an odd-cased iconv name"  => "iSo-2022-cN-eXt",
  "another iconv-only name"  => "IBM1047",
  "an iconv option suffix"   => "UTF-16//TRANSLIT",
  "the replacement encoding" => "iso-2022-kr",
  "x-user-defined"           => "x-user-defined",
  "windows-1258"             => "windows-1258",
  "an unknown name"          => "no-such-charset",
  "an empty label"           => "",
  "a blank label"            => "   ",
  "a 10 KB label"            => "a" * 10_240,
  "a padded 10 KB label"     => "utf-8" + " " * 10_240,
  "markup"                   => "<script>alert(1)</script>",
}

describe Amber::Router::Parsers::EncodingLabel do
  it "resolves every label of the standard to its encoding" do
    labels_by_name = whatwg_labels_by_name
    labels_by_name.size.should eq 40
    labels_by_name.values.sum(&.size).should eq 228

    labels_by_name.each do |name, list_of_labels|
      next if LIST_OF_ENCODINGS_WITHOUT_A_DECODER.includes?(name)
      list_of_labels.each do |label|
        encoding = Amber::Router::Parsers::EncodingLabel.resolve?(label)
        encoding.should_not be_nil, "#{label} did not resolve"
        encoding.try(&.name).should eq name
      end
    end
  end

  it "ignores letter case and surrounding ASCII whitespace" do
    ["UTF-8", "uTf-8", " utf-8\t", "\n\f\rLatin1 "].each do |label|
      Amber::Router::Parsers::EncodingLabel.resolve?(label).should_not be_nil
    end
    Amber::Router::Parsers::EncodingLabel.resolve?("Shift_JIS").try(&.name).should eq "Shift_JIS"
    Amber::Router::Parsers::EncodingLabel.resolve?("ISO-8859-1").try(&.name).should eq "windows-1252"
  end

  it "resolves no label of an encoding without a decoder" do
    labels_by_name = whatwg_labels_by_name
    LIST_OF_ENCODINGS_WITHOUT_A_DECODER.each do |name|
      labels_by_name[name].each do |label|
        Amber::Router::Parsers::EncodingLabel.resolve?(label).should be_nil
      end
    end
  end

  LIST_OF_REFUSED_CHARSETS.each do |description, charset|
    it "does not resolve #{description}" do
      Amber::Router::Parsers::EncodingLabel.resolve?(charset).should be_nil
    end
  end

  it "decodes ASCII with every decoder on this platform" do
    whatwg_labels_by_name.each do |name, list_of_labels|
      next if LIST_OF_ENCODINGS_WITHOUT_A_DECODER.includes?(name)
      body = name.starts_with?("UTF-16") ? "title=ok".encode(name) : "title=ok"
      request = form_request(list_of_labels.first, body)
      Amber::Router::Parsers::FormData.parse(request)["title"]?.should eq("ok"), "#{name} did not decode"
    end
  end
end

describe "a form's declared charset" do
  pipeline = Amber::Pipe::Pipeline.new

  before_each do
    Amber.env = :test
    FormCharsetController.action_calls = 0
    FormCharsetSpy.list_of_opened_converters.clear
    pipeline = Amber::Pipe::Pipeline.new
    Amber::Server.router.draw :web do
      post "/form-charset", FormCharsetController, :create
    end
    pipeline.build(:web) { plug Amber::Pipe::Error.new }
    pipeline.prepare_pipelines
  end

  LIST_OF_REFUSED_CHARSETS.each do |description, charset|
    it "answers 415 for #{description} without opening a converter" do
      error = expect_raises(Amber::Exceptions::UnsupportedCharset) do
        Amber::Router::Parsers::FormData.parse(form_request(charset))
      end
      error.status_code.should eq 415
      error.message.to_s.should_not contain("script")

      response = create_request_and_return_io(pipeline, form_request(charset))
      response.status_code.should eq 415
      response.body.should contain("declared charset is not supported")
      response.body.should_not contain("script")
      FormCharsetController.action_calls.should eq 0
      FormCharsetSpy.list_of_opened_converters.should be_empty
    end
  end

  it "leaves the body unread when it refuses the charset" do
    request = form_request("UTF-7")
    expect_raises(Amber::Exceptions::UnsupportedCharset) { Amber::Router::Parsers::FormData.parse(request) }
    request.body.try(&.gets_to_end).should eq "title=x"
  end

  it "answers 415 through the schema parsers" do
    error = expect_raises(Amber::Schema::RequestParseError) do
      Amber::Schema::Parser::ParserRegistry.parse_request(form_request("UTF-7"))
    end
    error.http_status.should eq 415
    error.code.should eq "unsupported_media_type"
  end

  it "parses every UTF-8 label without opening a converter" do
    whatwg_labels_by_name["UTF-8"].each do |label|
      response = create_request_and_return_io(pipeline, form_request(label.upcase, "title=caf%C3%A9"))
      response.status_code.should eq 200
      response.body.should eq "café"
    end
    FormCharsetSpy.list_of_opened_converters.should be_empty
  end

  it "decodes a form that ends in a letter above ASCII" do
    {"windows-1255" => {0xE0_u8, "א"}, "windows-1251" => {0xE0_u8, "а"}, "windows-1253" => {0xE1_u8, "α"}, "windows-874" => {0xA1_u8, "ก"}}.each do |label, (byte, letter)|
      request = form_request(label, "title=".to_slice + Bytes[byte])
      Amber::Router::Parsers::FormData.parse(request)["title"]?.should eq(letter), "#{label} lost its last letter"
    end
  end

  it "opens the decoder of the resolved encoding, never the client's name" do
    body = "title=caf".to_slice + Bytes[0xE9]
    response = create_request_and_return_io(pipeline, form_request("Latin1", body))
    response.status_code.should eq 200
    response.body.should eq "café"
    FormCharsetSpy.list_of_opened_converters.should eq ["CP1252"]
  end
end
