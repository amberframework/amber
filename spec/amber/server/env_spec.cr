require "../../../spec_helper"

describe Amber do
  {% for env in %w(development staging test sandbox production) %}
    describe ".{{env.id}}?" do
      it "returns true when the environment is {{env.id}}" do
        Amber::Settings.env = {{env}}
        Amber.env.{{env.id}}?.should be_truthy
      end

      it "returns false when the environment does not match" do
        Amber::Settings.env = "invalid environment"
        Amber.env.{{env.id}}?.should be_falsey
      end
    end
  {% end %}

  describe ".is?" do
    it "returns true when the environment matches the argument" do
      Amber::Settings.env = "staging"
      result = Amber.env.is? :staging

      result.should be_truthy
    end

    it "returns true when the environment matches the argument" do
      Amber::Settings.env = "invalid"
      result = Amber.env.is? :staging

      result.should be_falsey
    end
  end

  describe ".in?" do
    context "when settings environment is in list" do
      it "returns true" do
        Amber::Settings.env = "development"

        symbols_result = Amber.env.in? %i(development test production)
        strings_result = Amber.env.in? %w(development test production)

        symbols_result.should be_truthy
        strings_result.should be_truthy
      end
    end

    context "when settings environment is not in list" do
      it "returns false" do
        Amber::Settings.env = "invalid"

        symbols_result = Amber.env.in? %w(development test production)
        strings_result = Amber.env.in? %w(development test production)

        symbols_result.should be_falsey
        strings_result.should be_falsey
      end
    end
  end
end
