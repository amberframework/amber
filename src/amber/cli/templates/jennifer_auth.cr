require "./auth"

module Amber::CLI
  class JenniferAuth < Auth
    directory "#{__DIR__}/auth/jennifer"

    private def auth_fields
      [] of Field
    end

    private def id_field
      @fields.find { |field| field.name == "id" }
    end

    private def user_custom_fields
      @fields.select { |field| field.name != "id" }
    end

    private def timestamp_fields
      %w(created_at:time? updated_at:time?).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
    end

    private def controller_field_names
      array = [] of String
      timestamp_fields = %w(created_at updated_at)
      @fields.each do |f|
        next if timestamp_fields.includes?(f.name)
        array << (f.reference? ? "#{f.name}_id" : f.name)
      end
      array
    end
  end
end
