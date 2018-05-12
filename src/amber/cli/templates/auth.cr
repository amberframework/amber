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
    @database : String = CLI.config.database
    @language : String = CLI.config.language
    @timestamp : String
    @primary_key : String

    def initialize(@name, fields)
      @fields = all_fields(fields)
      @timestamp = Time.now.to_s("%Y%m%d%H%M%S%L")
      @primary_key = primary_key
      @visible_fields = @fields.reject(&.hidden).map(&.name)
      setup_routes
      setup_plugs
      setup_dependencies
      setup_application_controller
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
      require "../src/pipes/**"
      DEPENDENCY
    end

    private def setup_application_controller
      filename = "./src/controllers/application_controller.cr"
      controller = File.read(filename)
      append_text = ""

      unless controller.includes? "property current_#{@name}"
        append_text += current_method_definition
      end

      unless controller.includes? "def signed_in?"
        append_text += signed_in_method_definition
      end

      unless controller.includes? "def redirect_signed_out_#{@name}"
        append_text += redirect_signed_out_method_definition
      end

      append_text = "#{append_text}\nend\n"
      controller = controller.gsub(/end\s*\Z/, append_text)
      File.write(filename, controller)
    end

    private def current_method_definition
      <<-AUTH

        def current_#{@name}
          context.current_#{@name}
        end
      AUTH
    end

    private def signed_in_method_definition
      <<-AUTH

        def signed_in?
          current_#{@name} ? true : false
        end\n
      AUTH
    end

    private def redirect_signed_out_method_definition
      <<-AUTH

        private def redirect_signed_out_#{@name}
          unless signed_in?
            flash[:info] = "Must be logged in"
            redirect_to "/signin"
          end
        end\n
      AUTH
    end

    private def all_fields(fields)
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
