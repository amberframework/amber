module Amber::Router
  # Built-in regex presets for common parameter constraint patterns.
  # These can be referenced by symbol name in route definitions.
  CONSTRAINT_PRESETS = {
    :numeric => /\A\d+\z/,
    :uuid    => /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i,
    :slug    => /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
    :alpha   => /\A[a-zA-Z]+\z/,
    :alnum   => /\A[a-zA-Z0-9]+\z/,
    :hex     => /\A[0-9a-fA-F]+\z/,
  }
end
