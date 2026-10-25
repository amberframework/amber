# Standalone program compiled by spec/amber/validations/params_spec.cr.
#
# It calls the deprecated `Amber::Validators::Params#validation` entry point
# directly, so the compiler reports its deprecation warning here instead of in
# the warning-free spec build. Each output line is a `key=value` pair that the
# spec checks.
require "../../../src/amber"

request = HTTP::Request.new("GET", "/")
raw_params = Amber::Router::Params.new(request)
raw_params["last_name"] = "perez"
validator = Amber::Validators::Params.new(raw_params)

returned_validator = validator.validation do
  required(:name)
  required(:last_name) { |value| value == "perez" }
  optional(:nickname)
end

valid = validator.valid?

STDOUT.puts "returns_self=#{returned_validator.same?(validator)}"
STDOUT.puts "rule_count=#{validator.rules.size}"
STDOUT.puts "valid=#{valid}"
STDOUT.puts "error_fields=#{validator.errors.map(&.param).join(",")}"
STDOUT.puts "validated_fields=#{validator.params.keys.sort!.join(",")}"
