require "./validators/*"

module Contract
  include Validators

  VALIDATOR = {
    eq:     Equal,
    ex:     Exclusion,
    gt:     GreaterThan,
    gte:    GreaterThanOrEqual,
    in:     Inclusion,
    lt:     LessThan,
    lte:    LessThanOrEqual,
    regex:  RegularExpression,
    length: Length,
  }
end
