# Result object for schema validation and parsing operations
# Implements a functional programming pattern with immutable Success/Failure variants
module Amber::Schema
  # Success variant containing validated data
  class Success(T)
    getter value : T

    def initialize(@value : T)
    end

    def success? : Bool
      true
    end

    def failure? : Bool
      false
    end

    def error : ValidationFailure?
      nil
    end

    # Functor map - transforms the success value
    def map(&block : T -> U) forall U
      Success(U).new(yield @value)
    end

    # Monadic bind - chains operations that return Results
    def flat_map(&block : T -> Success(U) | Failure(U)) forall U
      yield @value
    end

    # Returns self since this is already a success
    def or_else(&block : ValidationFailure -> Success(T) | Failure(T))
      self
    end

    # Pattern matching support
    def on_success(&block : T ->)
      yield @value
      self
    end

    def on_failure(&block : ValidationFailure ->)
      self
    end

    def to_h
      {
        "success" => true,
        "data"    => @value,
      }
    end
  end

  # Failure variant containing validation errors
  class Failure(T)
    getter error : ValidationFailure

    def initialize(@error : ValidationFailure)
    end

    def success? : Bool
      false
    end

    def failure? : Bool
      true
    end

    def value : T?
      nil
    end

    # Map has no effect on failures
    def map(&block : T -> U) forall U
      Failure(U).new(@error)
    end

    # Flat map has no effect on failures
    def flat_map(&block : T -> Success(U) | Failure(U)) forall U
      Failure(U).new(@error)
    end

    # Attempts to recover from the failure
    def or_else(&block : ValidationFailure -> Success(T) | Failure(T))
      yield @error
    end

    # Pattern matching support
    def on_success(&block : T ->)
      self
    end

    def on_failure(&block : ValidationFailure ->)
      yield @error
      self
    end

    def to_h
      {
        "success" => false,
        "error"   => @error.to_h,
      }
    end
  end

  # Type alias for Result - defined as a module to avoid naming conflicts
  module Result(T)
    # Factory method to create Success
    def self.success(value : T) : Success(T) | Failure(T)
      Success(T).new(value)
    end

    # Factory method to create Failure
    def self.failure(error : ValidationFailure) : Success(T) | Failure(T)
      Failure(T).new(error)
    end
  end

  # Base class for validation errors (contains multiple field errors)
  class ValidationFailure
    getter errors : Array(Error)
    getter raw_data : Hash(String, JSON::Any)?
    getter warnings : Array(Warning)

    def initialize(@errors : Array(Error), @raw_data : Hash(String, JSON::Any)? = nil, @warnings : Array(Warning) = [] of Warning)
    end

    # Get all error messages as strings
    def messages : Array(String)
      @errors.map { |e| e.message || "Unknown error" }
    end

    # Get errors grouped by field
    def errors_by_field : Hash(String, Array(Error))
      @errors.group_by(&.field)
    end

    # Check if specific field has errors
    def has_error_for_field?(field : String) : Bool
      @errors.any? { |e| e.field == field }
    end

    # Get errors for specific field
    def errors_for_field(field : String) : Array(Error)
      @errors.select { |e| e.field == field }
    end

    # Convert to hash for JSON serialization
    def to_h
      {
        "errors"   => @errors.map(&.to_h),
        "warnings" => @warnings.map(&.to_h),
        "raw_data" => @raw_data,
      }
    end

    # Human-readable error summary
    def to_s(io)
      io << "Validation failed with #{@errors.size} error(s):\n"
      @errors.each do |error|
        io << "  - #{error.field}: #{error.message || "Unknown error"}\n"
      end
    end
  end

  # Base class for validated requests
  # Subclasses should define specific typed properties
  abstract class ValidatedRequest
    # Override in subclasses to provide the schema class
    macro inherited
      def self.schema_class : Definition.class
        raise "Must override schema_class in #{self}"
      end
    end

    # Factory method to create from raw data
    def self.from_raw_data(data : Hash(String, JSON::Any)) : Success(self) | Failure(self)
      schema = schema_class.new(data)
      result = schema.validate

      if result.success?
        # Create instance of the concrete ValidatedRequest subclass
        Success(self).new(new(result.data.not_nil!))
      else
        Failure(self).new(ValidationFailure.new(result.errors, data, result.warnings))
      end
    end

    # Initialize with validated data
    def initialize(@validated_data : Hash(String, JSON::Any))
    end

    # Access to raw validated data
    getter validated_data : Hash(String, JSON::Any)

    # Convert to hash
    def to_h : Hash(String, JSON::Any)
      @validated_data
    end
  end

  # Legacy Result class for backward compatibility
  # This maintains the existing API while using the new Result types internally
  class LegacyResult
    # Status of the validation/parsing operation
    getter success : Bool
    getter errors : Array(Error) = [] of Error
    getter warnings : Array(Warning) = [] of Warning

    # Validated and transformed data
    getter data : Hash(String, JSON::Any)?

    # Original input data (for debugging)
    getter original_data : Hash(String, JSON::Any)?

    def initialize(@success : Bool, @data : Hash(String, JSON::Any)? = nil, @original_data : Hash(String, JSON::Any)? = nil)
    end

    # Factory methods for creating results
    def self.success(data : Hash(String, JSON::Any))
      new(true, data)
    end

    def self.failure(errors : Array(Error), original_data : Hash(String, JSON::Any)? = nil)
      result = new(false, nil, original_data)
      result.errors.concat(errors)
      result
    end

    # Check if validation/parsing was successful
    def success?
      @success
    end

    def failure?
      !@success
    end

    # Add an error to the result
    def add_error(error : Error)
      @errors << error
      @success = false
    end

    # Add a warning (non-fatal issue)
    def add_warning(warning : Warning)
      @warnings << warning
    end

    # Get all error messages as strings
    def error_messages : Array(String)
      @errors.map { |e| e.message || "Unknown error" }
    end

    # Get errors grouped by field
    def errors_by_field : Hash(String, Array(Error))
      @errors.group_by(&.field)
    end

    # Convert result to a hash suitable for JSON response
    def to_h
      {
        "success"  => @success,
        "data"     => @data,
        "errors"   => @errors.map(&.to_h),
        "warnings" => @warnings.map(&.to_h),
      }
    end

    # Convert to new Result type - only works for types that can be constructed from Hash
    def to_typed_result : Success(Hash(String, JSON::Any)) | Failure(Hash(String, JSON::Any))
      if @success && @data
        Success(Hash(String, JSON::Any)).new(@data.not_nil!)
      else
        Failure(Hash(String, JSON::Any)).new(ValidationFailure.new(@errors, @original_data, @warnings))
      end
    end
  end

  # Helper module for working with Results
  module ResultHelpers
    # Try multiple validations and return the first success
    def self.first_success(results : Array(Success(T) | Failure(T))) forall T
      results.each do |result|
        return result if result.is_a?(Success)
      end
      results.last # Return last failure if all failed
    end

    # Combine multiple results into a single result
    def self.combine(results : Array(Success(T) | Failure(T))) forall T
      values = [] of T
      all_errors = [] of Error
      all_warnings = [] of Warning

      results.each do |result|
        case result
        when Success
          values << result.value
        when Failure
          all_errors.concat(result.error.errors)
          all_warnings.concat(result.error.warnings)
        end
      end

      if all_errors.empty?
        Success(Array(T)).new(values)
      else
        Failure(Array(T)).new(ValidationFailure.new(all_errors, nil, all_warnings))
      end
    end

    # Sequence a hash of results into a result of hash
    def self.sequence(results : Hash(String, Success(T) | Failure(T))) forall T
      values = {} of String => T
      all_errors = [] of Error
      all_warnings = [] of Warning

      results.each do |key, result|
        case result
        when Success
          values[key] = result.value
        when Failure
          all_errors.concat(result.error.errors)
          all_warnings.concat(result.error.warnings)
        end
      end

      if all_errors.empty?
        Success(Hash(String, T)).new(values)
      else
        Failure(Hash(String, T)).new(ValidationFailure.new(all_errors, nil, all_warnings))
      end
    end
  end
end
