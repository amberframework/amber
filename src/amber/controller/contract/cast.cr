module Contract
  module Cast
    def self.convert!(value : Contract::Validation::Any, cast_type : Class)
      case cast_type
      when String.class  then value.to_s
      when Bool.class    then [1, "true", "yes"].includes?(value)
      when Int32.class   then value.is_a?(String) ? value.to_i32(strict: false) : value.as(Int32)
      when Int64.class   then value.is_a?(String) ? value.to_i64(strict: false) : value.as(Int64)
      when Float32.class then value.is_a?(String) ? value.to_f32(strict: false) : value.as(Float32)
      when Float64.class then value.is_a?(String) ? value.to_f64(strict: false) : value.as(Float64)
      else                    value
      end
    end
  end
end
