# Error formatting utilities for responses
module Amber::Schema::ResponseFormatters
  class ErrorFormatter
    # Error grouping strategies
    enum GroupBy
      Field # Group errors by field name
      Code  # Group errors by error code
      None  # Flat list of errors
    end

    # Error detail level
    enum DetailLevel
      Minimal  # Just message
      Standard # Field, message, code
      Full     # All error details including metadata
    end

    getter group_by : GroupBy
    getter detail_level : DetailLevel
    getter include_field_path : Bool

    def initialize(
      @group_by : GroupBy = GroupBy::Field,
      @detail_level : DetailLevel = DetailLevel::Standard,
      @include_field_path : Bool = true,
    )
    end

    # Format an array of errors
    def format(errors : Array(Error)) : JSON::Any
      return JSON::Any.new([] of JSON::Any) if errors.empty?

      case @group_by
      when GroupBy::Field
        format_grouped_by_field(errors)
      when GroupBy::Code
        format_grouped_by_code(errors)
      else
        format_flat(errors)
      end
    end

    private def format_grouped_by_field(errors : Array(Error)) : JSON::Any
      grouped = {} of String => JSON::Any

      errors.group_by(&.field).each do |field, field_errors|
        grouped[field] = JSON::Any.new(
          field_errors.map { |error| format_single_error(error) }
        )
      end

      JSON::Any.new(grouped)
    end

    private def format_grouped_by_code(errors : Array(Error)) : JSON::Any
      grouped = {} of String => JSON::Any

      errors.group_by(&.code).each do |code, code_errors|
        grouped[code] = JSON::Any.new(
          code_errors.map { |error| format_single_error(error) }
        )
      end

      JSON::Any.new(grouped)
    end

    private def format_flat(errors : Array(Error)) : JSON::Any
      JSON::Any.new(errors.map { |error| format_single_error(error) })
    end

    private def format_single_error(error : Error) : JSON::Any
      case @detail_level
      when DetailLevel::Minimal
        JSON::Any.new(error.message)
      when DetailLevel::Standard
        hash = {} of String => JSON::Any
        hash["message"] = JSON::Any.new(error.message)
        hash["code"] = JSON::Any.new(error.code)
        hash["field"] = JSON::Any.new(error.field) if @include_field_path && !error.field.empty?
        JSON::Any.new(hash)
      else # DetailLevel::Full
        JSON::Any.new(error.to_h)
      end
    end

    # Create human-readable error summary
    def self.summarize(errors : Array(Error)) : String
      return "No errors" if errors.empty?

      if errors.size == 1
        errors.first.message
      else
        field_count = errors.map(&.field).uniq.size
        "#{errors.size} validation errors in #{field_count} fields"
      end
    end

    # Create detailed error report (for logging/debugging)
    def self.detailed_report(errors : Array(Error)) : String
      lines = ["Validation Errors:"]

      errors.group_by(&.field).each do |field, field_errors|
        lines << "\n  Field: #{field.empty? ? "(general)" : field}"
        field_errors.each do |error|
          lines << "    - #{error.message} (#{error.code})"
          if error.details
            lines << "      Details: #{error.details}"
          end
        end
      end

      lines.join("\n")
    end

    # Convert errors to HTML (for error pages)
    def self.to_html(errors : Array(Error)) : String
      return "" if errors.empty?

      html = %{<div class="validation-errors">}
      html += %{<h3>Validation Errors</h3>}
      html += %{<ul>}

      errors.each do |error|
        field_label = error.field.empty? ? "" : %{<strong>#{HTML.escape(error.field)}:</strong> }
        html += %{<li>#{field_label}#{HTML.escape(error.message)}</li>}
      end

      html += %{</ul>}
      html += %{</div>}

      html
    end
  end
end
