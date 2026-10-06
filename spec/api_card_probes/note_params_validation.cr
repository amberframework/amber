require "./probe_support"

context = Amber::Testing::ContextBuilder.new.query_param("name", "Ada").build
params = Amber::Validators::Params.new(context.params)
params.validation do
  required(:name) { |value| value.size > 1 }
end
validated_params = params.validate!
typeof(validated_params).should eq(Hash(String, String?))

schema_params = Amber::Controller::SchemaParamsWrapper.new(
  {} of String => JSON::Any,
  context.params
)
schema_params.validation do
  required(:name) { |value| value.size > 1 }
end.validate!
typeof(schema_params.to_h).should eq(Hash(String, String?))
