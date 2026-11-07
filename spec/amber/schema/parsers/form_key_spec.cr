require "../../../spec_helper"

describe Amber::Schema::Parser::FormKey do
  form_key = Amber::Schema::Parser::FormKey

  it "splits a key into its segments" do
    form_key.segments("user[tags][0]").should eq(["user", "tags", "0"])
    form_key.segments("plain").should eq(["plain"])
    form_key.segments("a[]").should eq(["a"])
    form_key.segments("").should be_empty
  end

  it "finds the name and index of an indexed key" do
    form_key.indexed_name_and_index("tags[12]").should eq({"tags", "12"})
    form_key.indexed_name_and_index("a[b][3]").should eq({"a[b]", "3"})
  end

  it "answers nil for any other key shape" do
    {"tags", "[1]", "tags[]", "tags[x]", "tags[1", "tags]"}.each do |key|
      form_key.indexed_name_and_index(key).should be_nil
    end
  end

  it "recognizes integers" do
    {"0", "12", "-3"}.each { |text| form_key.integer?(text).should be_true }
    {"", "-", "1.5", "a", "1 "}.each { |text| form_key.integer?(text).should be_false }
  end

  it "recognizes decimals" do
    {"1", "-1", "1.5", ".5", "2e10", "2E-3", "1.5e+2"}.each { |text| form_key.decimal?(text).should be_true }
    {"", ".", "1.", "e5", "1e", "1e+", "1.2.3", "abc", "1.5x"}.each { |text| form_key.decimal?(text).should be_false }
  end
end
