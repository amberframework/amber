require "../../spec_helper"

# The patterns these checks replaced. Each check must answer exactly as its
# pattern does, so an upgrade changes no application's validation.
private FORMER_EMAIL       = /\A[a-zA-Z0-9._%+-]+@[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}\z/
private FORMER_LOOSE_EMAIL = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
private FORMER_WEB_ADDRESS = /\A(https?:\/\/)?([\da-z\.-]+)\.([a-z\.]{2,6})([\/\w \.-]*)*\/?\z/
private FORMER_LOCATION    = /^(http(s)?(:\/\/))?(www\.)?[a-zA-Z0-9-_\.]+(\.[a-zA-Z0-9]{2,})([-a-zA-Z0-9:%_\+.~#?&\/\/=]*)/
private FORMER_UUID        = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/
private FORMER_IPV4        = /\A((25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\z/
private FORMER_IPV6        = /\A(([0-9a-fA-F]{1,4}:){7,7}[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,7}:|([0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}|([0-9a-fA-F]{1,4}:){1,5}(:[0-9a-fA-F]{1,4}){1,2}|([0-9a-fA-F]{1,4}:){1,4}(:[0-9a-fA-F]{1,4}){1,3}|([0-9a-fA-F]{1,4}:){1,3}(:[0-9a-fA-F]{1,4}){1,4}|([0-9a-fA-F]{1,4}:){1,2}(:[0-9a-fA-F]{1,4}){1,5}|[0-9a-fA-F]{1,4}:((:[0-9a-fA-F]{1,4}){1,6})|:((:[0-9a-fA-F]{1,4}){1,7}|:)|fe80:(:[0-9a-fA-F]{0,4}){0,4}%[0-9a-zA-Z]{1,}|::(ffff(:0{1,4}){0,1}:){0,1}((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])|([0-9a-fA-F]{1,4}:){1,4}:((25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9])\.){3,3}(25[0-5]|(2[0-4]|1{0,1}[0-9]){0,1}[0-9]))\z/
private FORMER_HOSTNAME    = /\A([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])(\.([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9\-]{0,61}[a-zA-Z0-9]))*\z/
private FORMER_PHONE       = /\A\+?[1-9]\d{5,14}\z/
private FORMER_TIME_OF_DAY = /\A([01]?[0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9]\z/

private SAMPLE_COUNT = 40_000

# Random strings built from pieces of the format, so most land near its boundary.
private def assert_same_answers(pattern : Regex, list_of_pieces : Array(String), seeds : Array(String), &check : String -> Bool) : Nil
  random = Random.new(20261106)
  accepted_count = 0

  list_of_samples = seeds + Array.new(SAMPLE_COUNT) do
    String.build do |text|
      random.rand(1..9).times { text << list_of_pieces.sample(random) }
    end
  end

  list_of_samples.each do |sample|
    # The former web address pattern gives up with an error on some short inputs, by
    # running out of backtracking steps. Those samples have no answer to compare.
    expected = begin
      pattern.matches?(sample)
    rescue Regex::Error
      next
    end
    accepted_count += 1 if expected
    fail "#{sample.inspect}: pattern says #{expected}" unless check.call(sample) == expected
  end

  accepted_count.should be > 0
  (accepted_count < list_of_samples.size).should be_true
end

private COMMON_PIECES = ["", " ", "\n", "\t", "é", "→", "@", ".", "-", "_", ":", "/", "%", "+"]

describe Amber::Support::TextFormats do
  text_formats = Amber::Support::TextFormats

  it "answers email as the former pattern did" do
    pieces = COMMON_PIECES + ["a", "Z", "9", "name", "example", "com", "io", "x.", "-b", "b-"]
    assert_same_answers(FORMER_EMAIL, pieces, ["a@b.co", "a.b+c%d_e-f@g-h.i.jk", "a@-b.co", "a@b-.co", "a@b.c", "a@b.c0", "a@@b.co", "@b.co", "a@.co"]) { |text| text_formats.email?(text) }
  end

  it "answers the loose email shape as the former pattern did" do
    pieces = COMMON_PIECES + ["a", "b", "\v", "\f", "\r", " ", "\u0085", "᠎", " ", "　", "​"]
    assert_same_answers(FORMER_LOOSE_EMAIL, pieces, ["a@b.c", "a@.c", "a@b.", "a@b..", "a@..", "é@→.ü", "a b@c.d", "a@b@c.d"]) { |text| text_formats.loose_email?(text) }
  end

  it "answers web address as the former pattern did" do
    pieces = COMMON_PIECES + ["http://", "https://", "http", "a", "Z", "0", "example", "com", ".co", "..", " x", "/path", "é"]
    assert_same_answers(FORMER_WEB_ADDRESS, pieces, ["example.com", "http://a.co/b c", "a.b", ".co", "a..", "A.com", "a.COM", "https://x.y.z/_-", "http:a.co", "a.co/"]) { |text| text_formats.web_address?(text) }
  end

  it "answers location prefix as the former url? pattern did" do
    pieces = COMMON_PIECES + ["http://", "https://", "www.", "a", "Z", "0", "example", ".co", ".c", "?q=1", "#x"]
    assert_same_answers(FORMER_LOCATION, pieces, ["example.com", "www.ab", "www.a", "/path", "http://a.bc/d?e", "http:a.bc", ".ab", "a.b", "a_b.cd", "-.cd"]) { |text| text_formats.location_prefix?(text) }
  end

  it "answers uuid as the former pattern did" do
    pieces = ["-", "1234", "abcd", "EF01", "12345678", "123456789abc", "g", "é", "\n"]
    assert_same_answers(FORMER_UUID, pieces, ["123e4567-e89b-12d3-a456-426614174000", "123E4567-E89B-12D3-A456-426614174000", "123e4567-e89b-12d3-a456-42661417400", "123e4567xe89b-12d3-a456-426614174000"]) { |text| text_formats.uuid?(text) }
  end

  it "answers ipv4 as the former pattern did" do
    pieces = [".", ".", ".", "0", "1", "9", "25", "255", "256", "199", "249", "099", "001", "1000", "a", "", "\n", "é"]
    assert_same_answers(FORMER_IPV4, pieces, ["0.0.0.0", "255.255.255.255", "256.0.0.1", "001.002.003.004", "1.2.3", "1.2.3.4.5", "1.2.3.4\n"]) { |text| text_formats.ipv4?(text) }
  end

  it "answers ipv6 as the former pattern did" do
    pieces = [":", ":", ":", "::", "1", "ab", "ABCD", "12345", "g", "fe80:", "fe80", "%", "eth0", "ffff", "ffff:", "FFFF:", "0", "0000", "00000", "1.2.3.4", "05.1.1.1", "005.1.1.1", "255.1.1.1", "256.1.1.1", ".", "é", "\n"]
    seeds = ["::", "::1", "1::", "1:2:3:4:5:6:7:8", "1:2:3:4:5:6:7::", "::2:3:4:5:6:7:8", "1::3:4:5:6:7:8", "1:2:3:4:5:6:7:8:9", "1::2::3", ":::",
             "fe80:%eth0", "fe80::%eth0", "fe80::1:2:3%eth0", "fe80::::%z", "fe80:::::%z", "fe80:1%z", "::1.2.3.4", "::ffff:1.2.3.4", "::ffff:0:1.2.3.4", "::ffff:00000:1.2.3.4",
             "::FFFF:1.2.3.4", "1::1.2.3.4", "1:2:3:4::1.2.3.4", "1:2:3:4:5::1.2.3.4", "::05.1.1.1", "::005.1.1.1", "::255.255.255.255", "::256.1.1.1", "::é"]
    assert_same_answers(FORMER_IPV6, pieces, seeds) { |text| text_formats.ipv6?(text) }
  end

  it "answers hostname as the former pattern did" do
    pieces = [".", "-", "a", "Z", "9", "a" * 30, "a" * 61, "a" * 63, "a" * 64, "_", "é", "\n", ""]
    assert_same_answers(FORMER_HOSTNAME, pieces, ["a", "a.b", "a-b.c", "-a", "a-", "a.", ".a", "", "a" * 63, "a" * 64]) { |text| text_formats.hostname?(text) }
  end

  it "answers phone as the former pattern did" do
    pieces = ["+", "0", "1", "9", "12345", "1234567", "a", "", " ", "\n", "é"]
    assert_same_answers(FORMER_PHONE, pieces, ["+123456", "123456", "12345", "012345", "1" * 15, "1" * 16, "++123456"]) { |text| text_formats.phone?(text) }
  end

  it "answers time of day as the former pattern did" do
    pieces = [":", ":", "0", "1", "9", "00", "09", "23", "24", "59", "60", "a", "", "\n", "é"]
    assert_same_answers(FORMER_TIME_OF_DAY, pieces, ["0:00:00", "23:59:59", "24:00:00", "1:2:3", "01:02", "01:02:03:04"]) { |text| text_formats.time_of_day?(text) }
  end

  it "accepts only ASCII digits in a phone number and a web host" do
    text_formats.phone?("١٢٣٤٥٦٧").should be_false
    text_formats.web_address?("١.com").should be_false
  end

  # What the former pattern answered for these depended on the PCRE2 version linked:
  # newer ones count them in `\w`. The check answers the same on every build.
  it "accepts connector punctuation and combining marks in a web address path" do
    {"‿", "⁀", "＿", "﹏", "́"}.each do |char|
      text_formats.web_address?("example.co/a#{char}b").should be_true
    end
  end

  it "answers a long hostile address in linear time" do
    hostile_text = "a.bc" + "/" * 60_000 + "!"
    elapsed = Time.measure { text_formats.web_address?(hostile_text).should be_false }
    elapsed.should be < 1.second
  end
end
