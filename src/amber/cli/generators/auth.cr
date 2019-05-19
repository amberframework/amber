require "./generator"
require "./field"

module Amber::CLI
  class Auth < Generator
    command :auth
    directory "#{__DIR__}/../templates/auth"

    property fields : Array(Field)

    def initialize(name, fields)
      super(name, nil)
      @fields = all_fields(fields)
    end

    def pre_render(directory, **args)
      add_routes
      add_plugs
      add_dependencies
      inject_application_controller_methods
    end

    private def add_routes
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

    private def add_plugs
      add_plugs :web, <<-PLUGS
        plug Authenticate.new
      PLUGS
    end

    private def add_dependencies
      add_dependencies <<-DEPENDENCY
      require "../src/models/**"
      require "../src/pipes/**"
      DEPENDENCY
    end

    private def inject_application_controller_methods
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
        end\n
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
        end
      AUTH
    end

    private def all_fields(fields)
      fields.map { |field| Field.new(field, database: config.database) } +
        auth_fields +
        timestamp_fields
    end

    private def auth_fields
      %w(email:string hashed_password:password).map do |f|
        Field.new(f, hidden: false, database: config.database)
      end
    end

    private def timestamp_fields
      %w(created_at:time updated_at:time).map do |f|
        Field.new(f, hidden: true, database: config.database)
      end
    end
  end
end
