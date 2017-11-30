require "./field.cr"
require "../helpers/migration"

module Amber::CLI
  class Auth < Teeplate::FileTree
    include Helpers
    include Helpers::Migration
    directory "#{__DIR__}/auth"

    @name : String
    @fields : Array(Field)
    @visible_fields : Array(String)
    @database : String
    @language : String
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @database = fetch_database
      @language = fetch_language
      @fields = setup_fields(fields)
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S%L")
      @primary_key = primary_key
      @visible_fields = @fields.reject(&.hidden).map(&.name)
      setup_routes
      setup_plugs
      setup_dependencies
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?(".#{@language}") }
    end

    private def setup_routes
      add_routes :web, <<-ROUTES
        get "/profile", #{class_name}Controller, :show
        get "/profile/edit", #{class_name}Controller, :edit
        patch "/profile", #{class_name}Controller, :update
        get "/signin", SessionController, :new
        post "/session", SessionController, :create
        get "/signout", SessionController, :delete
        get "/signup", RegistrationController, :new
        post "/registration", RegistrationController, :create
      ROUTES
    end

    private def setup_plugs
      add_plugs :web, <<-PLUGS
        plug Authenticate.new
      PLUGS
    end

    private def setup_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      require "../src/handlers/**"
      DEPENDENCY
    end

    private def setup_fields(fields)
      fields.map { |field| Field.new(field, database: @database) } +
      auth_fields +
      timestamp_fields
    end

    private def auth_fields
      %w(email:string hashed_password:password).map do |f|
        Field.new(f, hidden: false, database: @database)
      end
    end

    private def timestamp_fields
      %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
    end
  end
end
