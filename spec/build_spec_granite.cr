require "./build_spec_helper"

module Amber::CLI
  describe "building a generated app using granite model and slang template" do
    generate_app("new", "-m", "granite", "-t", "slang")
    check_formatting
    check_binary
    check_app_specs
  ensure
    cleanup
  end

  describe "building a generated app using granite model and ecr template" do
    generate_app("new", "-m", "granite", "-t", "ecr")
    check_formatting
    check_binary
    check_app_specs
  ensure
    cleanup
  end
end
