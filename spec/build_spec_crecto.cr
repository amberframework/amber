require "./build_spec_helper"

module Amber::CLI
  describe "building a generated app using crecto model and slang template" do
    generate_app("new", "-m", "crecto", "-t", "slang")
    check_formatting
    check_binary
    check_app_specs
  ensure
    cleanup
  end

  describe "building a generated app using crecto model and ecr template" do
    generate_app("new", "-m", "crecto", "-t", "ecr")
    check_formatting
    check_binary
    check_app_specs
  ensure
    cleanup
  end
end
