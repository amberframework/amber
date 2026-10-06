require "./probe_support"

context = Amber::Testing::ContextBuilder.new.query_param("name", "Ada").build
controller = APICardProbeController.new(context)
typeof(controller.exposed_legacy_params).should eq(Amber::Validators::Params)
typeof(controller.exposed_params).should eq(Amber::Controller::SchemaParamsWrapper | Amber::Validators::Params)
typeof(controller.exposed_raw_params).should eq(Amber::Router::Params)
