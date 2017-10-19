require "./field.cr"

module Amber::CLI
  class Auth < Teeplate::FileTree
    include Amber::CLI::Helpers
    directory "#{__DIR__}/auth"

    @name : String
    @fields : Array(Field)
    @visible_fields : Array(String)
    @database : String
    @language : String
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @database = database
      @language = language
      @fields = fields.map { |field| Field.new(field, database: @database) }
      @fields << Field.new("email:string", hidden: false, database: @database)
      @fields << Field.new("encrypted_password:password", hidden: false, database: @database)
      @fields += %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: @database)
      end
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S")
      @primary_key = primary_key
      @visible_fields = @fields.reject(&.hidden).map(&.name)

      add_routes :web, <<-ROUTES
        get "/signin", SessionController, :new
          post "/session", SessionController, :create
          get "/signout", SessionController, :delete
          get "/signup", RegistrationController, :new
          post "/registration", RegistrationController, :create
      ROUTES

      add_plugs :web, <<-PLUGS
        plug Authenticate.new
      PLUGS

      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      require "../src/handlers/**"
      DEPENDENCY
    end

    def database
      if File.exists?(DATABASE_YML) &&
         (yaml = YAML.parse(File.read DATABASE_YML)) &&
         (database = yaml.first)
        database.to_s
      else
        return "pg"
      end
    end

    def language
      if File.exists?(AMBER_YML) &&
         (yaml = YAML.parse(File.read AMBER_YML)) &&
         (language = yaml["language"]?)
        language.to_s
      else
        return "slang"
      end
    end

    def primary_key
      case @database
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

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?(".#{@language}") }
    end
  end
end
