module Amber::CLI
  module Jennifer
    class Migration < Amber::CLI::Migration
      directory "#{__DIR__}/migration/jennifer/empty"

      NEW_TABLE_REGEXP = /^create_([a-z][\w_\d]*)$/
      ADD_COLUMNS_REGEXP = /^add_.*_to_([a-z][\w_\d]*)$/
      REMOVE_COLUMNS_REGEXP = /^remove_.*_from_([a-z][\w_\d]*)$/

      getter table_name : String?

      def self.build(name, fields)
        type = extract_type(name, fields)
        if type == :unspecified
          self.new(name, fields)
        elsif type == :new
          CreateTableMigration.new(name, fields)
        else
          ChangeColumnsMigration.new(name, fields, type)
        end
      end

      private def self.extract_type(class_name, fields)
        if fields.empty? && !class_name.match(NEW_TABLE_REGEXP)
          :unspecified
        else
          case class_name
          when NEW_TABLE_REGEXP
            :new
          when ADD_COLUMNS_REGEXP
            :add
          when REMOVE_COLUMNS_REGEXP
            :remove
          else
            :unspecified
          end
        end
      end

      def up_definition; end
      def down_definition; end

      private def field_type(field)
        case field.type
        when "boolean"
          "bool"
        else
          field.type
        end
      end

      private def null_statement(field)
        field.nilable? ? ", {:null => true}" : ""
      end

      private def extra_fields
        [] of Field
      end
    end

    class CreateTableMigration < Migration
      directory "#{__DIR__}/migration/jennifer/create_table"

      def initialize(name, fields)
        super(name, fields)
        @table_name = name.match(NEW_TABLE_REGEXP).not_nil![1]
      end

      private def column_definition(field)
        "t.#{field_type(field)} :#{field.name}#{null_statement(field)}"
      end
    end

    class ChangeColumnsMigration < Migration
      directory "#{__DIR__}/migration/jennifer/change_columns"

      @type : Symbol

      def initialize(name, fields, @type)
        raise ArgumentError.new unless [:add, :remove].includes?(@type)
        super(name, fields)
        @table_name = name.match(add? ? ADD_COLUMNS_REGEXP : REMOVE_COLUMNS_REGEXP).not_nil![1]
      end

      def add?
        @type == :add
      end

      def remove?
        @type == :remove
      end

      private def add_column(field)
        "t.add_column :#{field.name}, :#{field_type(field)}#{null_statement(field)}"
      end

      private def remove_column(field)
        "t.drop_column :#{field.name}"
      end
    end
  end
end
