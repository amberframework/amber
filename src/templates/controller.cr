require "teeplate"
require "./field.cr"

module Amber::CMD
  class Controller < Teeplate::FileTree
    directory "#{__DIR__}/controller"

    @name : String
    @fields : Array(Field)
    @language : String

    def initialize(@name, fields)
      @language = language
      @fields = fields.map {|field| Field.new(field)}
      add_route
    end

    AMBER_YML = ".amber.yml"
    def language
      if File.exists?(AMBER_YML) &&
        (yaml = YAML.parse(File.read AMBER_YML)) &&
        (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def add_route
      routes = File.read("./config/routes.cr")
      @fields.map(&.name).map{|f| %Q(get "/#{@name}/#{f}", #{@name.capitalize}Controller, :#{f})}.join("\n    ")
      replacement = <<-ROUTE
      routes :web do
          #{@fields.map(&.name).map{|f| %Q(get "/#{@name}/#{f}/", #{@name.capitalize}Controller, :#{f})}.join("\n    ") }
      ROUTE
      File.write("./config/routes.cr", routes.gsub("routes :web do", replacement))
    end
  end
end
