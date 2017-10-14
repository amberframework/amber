require "../../../spec_helper"

describe Amber do
  {% for env in %w(development staging test sandbox production) %}
    describe ".{{env.id}}?" do
      it "returns true when the environment is {{env.id}}" do
        amber_env = Amber::Environment.new {{env}}
        amber_env.{{env.id}}?.should be_truthy
      end

      it "returns false when the environment does not match" do
        amber_env = Amber::Environment.new "invalid environment"
        amber_env.{{env.id}}?.should be_falsey
      end
    end
  {% end %}

  describe ".==" do
    it "returns true when the environment matches the argument(String)" do
      amber_env = Amber::Environment.new "staging"
      result = amber_env == "staging"

      result.should be_truthy
    end

    it "returns true when the environment matches the argument(Symbol)" do
      amber_env = Amber::Environment.new "staging"
      result = amber_env == :staging

      result.should be_truthy
    end

    it "returns false when the environment matches the argument" do
      amber_env = Amber::Environment.new "invalid"
      result = amber_env == :staging

      result.should be_falsey
    end
  end

  describe "!=" do
    it "returns true when the environment doesn't match the argument" do
      amber_env = Amber::Environment.new "invalid"
      result = amber_env != :staging

      result.should be_truthy
    end
  end

  describe ".in?" do
    context "when settings environment is in list" do
      it "returns true when array is passed in" do
        amber_env = Amber::Environment.new "development"

        symbols_result = amber_env.in? %i(development test production)
        strings_result = amber_env.in? %w(development test production)

        symbols_result.should be_truthy
        strings_result.should be_truthy
      end

      it "returns true when tuple is passed in" do
        amber_env = Amber::Environment.new "development"

        symbols_result = amber_env.in?(:development, :test, :production)
        strings_result = amber_env.in?("development", "test", "production")

        symbols_result.should be_truthy
        strings_result.should be_truthy
      end
    end

    context "when settings environment is not in list" do
      it "returns false" do
        amber_env = Amber::Environment.new "invalid"

        symbols_result = amber_env.in? %w(development test production)
        strings_result = amber_env.in? %w(development test production)

        symbols_result.should be_falsey
        strings_result.should be_falsey
      end
    end
  end
end
