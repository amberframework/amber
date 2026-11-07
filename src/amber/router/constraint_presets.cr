require "./param_constraints"

module Amber::Router
  # The route parameter rules a route can name by symbol, such as
  # `{"id" => :numeric}`. The same table as `ParamConstraints::PRESETS`.
  CONSTRAINT_PRESETS = ParamConstraints::PRESETS
end
