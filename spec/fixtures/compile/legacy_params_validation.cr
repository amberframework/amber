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

# A second call covers the rule options that the first leaves out: a blank
# value accepted through `allow_blank: true`, and optional rules whose
# parameter is present, so their blocks run (one passes, one fails).
blank_request = HTTP::Request.new("GET", "/")
blank_params = Amber::Router::Params.new(blank_request)
blank_params["name"] = " "
blank_params["middle"] = "x"
blank_params["nickname"] = "kit"
blank_validator = Amber::Validators::Params.new(blank_params)

blank_validator.validation do
  required(:name, allow_blank: true)
  optional(:middle) { |value| value == "j" }
  optional(:nickname) { |value| value == "kit" }
end

blank_valid = blank_validator.valid?

STDOUT.puts "options.valid=#{blank_valid}"
STDOUT.puts "options.error_fields=#{blank_validator.errors.map(&.param).join(",")}"
STDOUT.puts "options.validated_fields=#{blank_validator.params.keys.sort!.join(",")}"
