require "../../spec_helper"

class PatternEngineFieldSchema < Amber::Schema::Definition
  field :code, String, pattern: "^A+$"
end

class PatternEngineMacroSchema < Amber::Schema::Definition
  include Amber::Schema::DSL

  field :code, String
  validates_pattern :code, "^A+$"
  field :sku, String
  validates_format :sku, "^B+$"
end

describe Amber::Schema::PatternEngine do
  it "runs a pattern declared on a field" do
    Amber::Schema::PatternEngine.matches?("^A+$", "AAA").should be_true
    Amber::Schema::PatternEngine.matches?("^A+$", "AB").should be_false
  end

  it "runs patterns declared with validates_pattern and validates_format" do
    valid_schema = PatternEngineMacroSchema.new(JSON.parse(%({"code":"AAA","sku":"BB"})).as_h)
    valid_schema.validate.success?.should be_true

    invalid_schema = PatternEngineMacroSchema.new(JSON.parse(%({"code":"x","sku":"y"})).as_h)
    invalid_schema.validate.success?.should be_false
  end
end
