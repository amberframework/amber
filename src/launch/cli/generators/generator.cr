require "../helpers/migration"
require "./field.cr"

module Launch::CLI
  abstract class Generator < Teeplate::FileTree
    class_getter registered_commands = Hash(String, Launch::CLI::Generator.class).new

    macro command(name)
      Launch::CLI::Generator.registered_commands[{{name.id.stringify}}] = {{ @type.id }}
    end

    include Helpers::Migration
    include Helpers

    property name : String
    property fields : Array(Field)
    property fields_hash : Hash(String, String)
    property config : Launch::CLI::Config
    property table_name : String?
    property timestamp : String

    def initialize(@name, params)
      @config = CLI.config
      @table_name ||= name_plural
      @fields = parse_fields(params)
      @fields_hash = parse_fields_hash
      @timestamp = Time.utc.to_s("%Y%m%d%H%M%S%L")
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{config.language}") }
    end

    def render(directory, **args)
      pre_render(directory, **args)
      super(directory, **args)
      post_render(directory, **args)
    end

    def pre_render(directory, **args)
    end

    def post_render(directory, **args)
    end

    def add_timestamp_fields
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: config.database)
      end
    end

    private def parse_fields(params : Array(String)?) : Array(Field)
      if params
        fields = params.map { |field| Field.new(field, database: config.database) }
      else
        fields = [] of Field
      end
      fields
    end

    private def parse_fields_hash
      fields_hash = Hash(String, String).new
      @fields.reject(&.hidden).each do |f|
        field_name = f.reference? ? "#{f.name}_id" : f.name
        fields_hash[field_name] = default_value(f.cr_type) unless f.nil?
      end
      fields_hash
    end

    private def default_value(field_type)
      case field_type.downcase
      when "int32", "int64", "integer"
        "1"
      when "float32", "float64", "float"
        "1.00"
      when "bool", "boolean"
        "true"
      when "time", "timestamp"
        Time.utc.to_s
      when "ref", "reference", "references"
        rand(100).to_s
      else
        "Fake"
      end
    end
  end
end
