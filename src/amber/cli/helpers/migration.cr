module Amber::CLI::Helpers::Migration
  def create_index_for_reference_fields_sql
    sql_statements = reference_fields.map do |field|
      create_index_for_reference_field_sql(field)
    end
    sql_statements.join("\n")
  end

  def create_table_sql
    <<-SQL
    CREATE TABLE #{@name}s (
      #{@primary_key},
      #{create_table_fields_sql}
    );
    SQL
  end

  def drop_table_sql
    "DROP TABLE IF EXISTS #{@name}s;"
  end

  def primary_key
    case CLI.config.database
    when "pg"
      "id BIGSERIAL PRIMARY KEY"
    when "mysql"
      "id BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY"
    when "sqlite"
      "id INTEGER NOT NULL PRIMARY KEY"
    else
      "id INTEGER NOT NULL PRIMARY KEY"
    end
  end

  private def create_index_for_reference_field_sql(field : Field)
    index_name = "#{@name.underscore}_#{field.name}_id_idx"
    <<-SQL
    CREATE INDEX #{index_name} ON #{@name}s (#{field.name}_id);
    SQL
  end

  private def create_table_field_sql(field : Field)
    "#{field.name}#{field.reference? ? "_id" : ""} #{field.db_type}"
  end

  private def create_table_fields_sql
    @fields.map { |field| create_table_field_sql(field) }.join(",\n  ")
  end

  private def reference_fields
    @fields.select(&.reference?)
  end
end
