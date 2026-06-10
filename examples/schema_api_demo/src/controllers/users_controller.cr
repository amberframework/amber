# Users Controller demonstrating Schema API integration
require "../schemas/user_schemas"
require "../models/user"

class UsersController < Amber::Controller::Base
  include Amber::Schema::ControllerIntegration

  # Seed demo data on first request
  before_action :ensure_demo_data

  # GET /users
  # List users with filtering and pagination
  def index
    # Parse and validate query parameters
    search_schema = Schemas::UserSearchSchema.new(query_params_hash)
    result = search_schema.validate

    if result.failure?
      return respond_with_errors(result.errors)
    end

    # Extract validated parameters
    query = search_schema.q
    role = search_schema.role
    is_active = search_schema.is_active
    tags = search_schema.tags
    page = search_schema.page || 1
    per_page = search_schema.per_page || 20
    sort_by = search_schema.sort_by || "created_at"
    sort_order = search_schema.sort_order || "desc"

    # Perform search
    users = Models::User.search(query, role, is_active, tags)

    # Sort users
    users = sort_users(users, sort_by, sort_order)

    # Paginate
    total = users.size
    offset = (page - 1) * per_page
    users = users[offset, per_page] || [] of Models::User

    # Build response
    response_data = {
      "users"      => JSON::Any.new(users.map(&.to_h)),
      "pagination" => JSON::Any.new({
        "page"        => JSON::Any.new(page),
        "per_page"    => JSON::Any.new(per_page),
        "total"       => JSON::Any.new(total),
        "total_pages" => JSON::Any.new((total / per_page.to_f).ceil.to_i),
      }),
    }

    respond_with(response_data)
  end

  # GET /users/:id
  # Show a single user
  def show
    user_id = params[:id].to_i64

    if user = Models::User.find(user_id)
      respond_with({"user" => user.to_h})
    else
      respond_with_error("User not found", 404, "user_not_found")
    end
  end

  # POST /users
  # Create a new user with schema validation
  def create
    # Parse request body
    create_schema = Schemas::CreateUserSchema.new(request_body_hash)
    result = create_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Create user (password would be hashed in real app)
    user_params = result.data.not_nil!.dup
    user_params.delete("password")
    user_params.delete("password_confirmation")

    user = Models::User.create(user_params)

    respond_with({"user" => user.to_h}, 201)
  end

  # PATCH/PUT /users/:id
  # Update an existing user
  def update
    user_id = params[:id].to_i64

    unless user = Models::User.find(user_id)
      return respond_with_error("User not found", 404, "user_not_found")
    end

    # Validate update data
    update_schema = Schemas::UpdateUserSchema.new(request_body_hash)
    result = update_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Update user
    user.update(result.data.not_nil!)

    respond_with({"user" => user.to_h})
  end

  # DELETE /users/:id
  # Delete a user
  def destroy
    user_id = params[:id].to_i64

    if user = Models::User.find(user_id)
      user.destroy
      respond_with({"message" => JSON::Any.new("User deleted successfully")})
    else
      respond_with_error("User not found", 404, "user_not_found")
    end
  end

  # POST /users/:id/activate
  # Activate a user account
  def activate
    user_id = params[:id].to_i64

    unless user = Models::User.find(user_id)
      return respond_with_error("User not found", 404, "user_not_found")
    end

    if user.is_active
      return respond_with_error("User is already active", 400, "already_active")
    end

    # Validate activation parameters
    activation_schema = Schemas::UserActivationSchema.new(request_body_hash)
    result = activation_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Activate user
    user.activate!

    # In real app, would send notification if requested
    if activation_schema.notify_user
      # Send email notification
    end

    respond_with({
      "user"    => user.to_h,
      "message" => JSON::Any.new("User activated successfully"),
    })
  end

  # POST /users/:id/deactivate
  # Deactivate a user account
  def deactivate
    user_id = params[:id].to_i64

    unless user = Models::User.find(user_id)
      return respond_with_error("User not found", 404, "user_not_found")
    end

    if !user.is_active
      return respond_with_error("User is already inactive", 400, "already_inactive")
    end

    # Validate deactivation parameters
    deactivation_schema = Schemas::UserActivationSchema.new(request_body_hash)
    result = deactivation_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Deactivate user
    user.deactivate!

    respond_with({
      "user"    => user.to_h,
      "message" => JSON::Any.new("User deactivated successfully"),
    })
  end

  # POST /users/bulk
  # Create multiple users at once
  def bulk_create
    bulk_schema = Schemas::BulkCreateUsersSchema.new(request_body_hash)
    result = bulk_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    created_users = [] of Models::User
    errors = [] of Hash(String, JSON::Any)

    # Process each user
    if users_data = result.data.not_nil!["users"].as_a
      users_data.each_with_index do |user_data, index|
        begin
          user_hash = user_data.as_h
          # Remove password fields before creating
          user_hash.delete("password")
          user_hash.delete("password_confirmation")

          user = Models::User.create(user_hash)
          created_users << user
        rescue ex
          errors << {
            "index" => JSON::Any.new(index),
            "error" => JSON::Any.new(ex.message || "Failed to create user"),
          }
        end
      end
    end

    response_data = {
      "created" => JSON::Any.new(created_users.map(&.to_h)),
      "errors"  => JSON::Any.new(errors),
      "summary" => JSON::Any.new({
        "requested" => JSON::Any.new(users_data.try(&.size) || 0),
        "created"   => JSON::Any.new(created_users.size),
        "failed"    => JSON::Any.new(errors.size),
      }),
    }

    status = errors.empty? ? 201 : 207 # 207 Multi-Status
    respond_with(response_data, status)
  end

  # DELETE /users/bulk
  # Delete multiple users at once
  def bulk_delete
    bulk_schema = Schemas::BulkDeleteUsersSchema.new(request_body_hash)
    result = bulk_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    deleted_count = 0
    if ids = result.data.not_nil!["ids"].as_a
      ids.each do |id_value|
        if id = id_value.as_i64?
          if user = Models::User.find(id)
            user.destroy
            deleted_count += 1
          end
        end
      end
    end

    respond_with({
      "deleted_count" => JSON::Any.new(deleted_count),
      "message"       => JSON::Any.new("Users deleted successfully"),
    })
  end

  # GET /users/search
  # Advanced search endpoint
  def search
    # This is similar to index but could have additional search features
    index
  end

  # GET /users/:id/posts
  # Get user's posts (simulated)
  def posts
    user_id = params[:id].to_i64

    unless user = Models::User.find(user_id)
      return respond_with_error("User not found", 404, "user_not_found")
    end

    # Simulated posts data
    posts = [
      {
        "id"         => JSON::Any.new(1),
        "title"      => JSON::Any.new("My First Post"),
        "content"    => JSON::Any.new("This is the content of my first post"),
        "created_at" => JSON::Any.new(Time.utc.to_s),
      },
      {
        "id"         => JSON::Any.new(2),
        "title"      => JSON::Any.new("Another Post"),
        "content"    => JSON::Any.new("More interesting content here"),
        "created_at" => JSON::Any.new(Time.utc.to_s),
      },
    ]

    respond_with({
      "user_id" => JSON::Any.new(user_id),
      "posts"   => JSON::Any.new(posts),
    })
  end

  # GET /users/export
  # Export users to various formats
  def export
    export_schema = Schemas::UserExportSchema.new(query_params_hash)
    result = export_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Get users based on filters
    users = Models::User.all
    unless export_schema.include_inactive
      users = users.select(&.is_active)
    end

    # Filter by date range if provided
    if date_from = export_schema.date_from
      # In real app, would filter by created_at
    end

    format = export_schema.format || "json"
    fields = export_schema.fields || ["id", "email", "username", "created_at"]

    case format
    when "json"
      export_data = users.map do |user|
        user_hash = user.to_h
        filtered_hash = {} of String => JSON::Any
        fields.each do |field|
          if user_hash.has_key?(field)
            filtered_hash[field] = user_hash[field]
          end
        end
        filtered_hash
      end

      respond_with({"users" => JSON::Any.new(export_data)})
    when "csv"
      # Generate CSV
      csv_content = String.build do |io|
        io << fields.join(",") << "\n"
        users.each do |user|
          user_hash = user.to_h
          values = fields.map do |field|
            value = user_hash[field]?
            value ? value.to_s.gsub("\"", "\"\"") : ""
          end
          io << values.map { |v| %("#{v}") }.join(",") << "\n"
        end
      end

      response.content_type = "text/csv"
      response.headers["Content-Disposition"] = "attachment; filename=\"users_export.csv\""
      response.print csv_content
      response.close
    when "xml"
      # Generate XML
      xml_content = String.build do |io|
        io << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        io << "<users>\n"
        users.each do |user|
          io << "  <user>\n"
          user_hash = user.to_h
          fields.each do |field|
            if value = user_hash[field]?
              io << "    <#{field}>#{XML.escape(value.to_s)}</#{field}>\n"
            end
          end
          io << "  </user>\n"
        end
        io << "</users>"
      end

      response.content_type = "application/xml"
      response.print xml_content
      response.close
    else
      respond_with_error("Unsupported format", 400, "unsupported_format")
    end
  end

  # POST /users/import
  # Import users from file
  def import
    import_schema = Schemas::UserImportSchema.new(request_body_hash)
    result = import_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # In real app, would process the uploaded file
    # For demo, just return a simulated result

    dry_run = import_schema.dry_run || false
    skip_errors = import_schema.skip_errors || false

    response_data = {
      "status"  => JSON::Any.new(dry_run ? "dry_run_completed" : "import_completed"),
      "summary" => JSON::Any.new({
        "total_rows" => JSON::Any.new(10),
        "imported"   => JSON::Any.new(dry_run ? 0 : 8),
        "skipped"    => JSON::Any.new(2),
        "errors"     => JSON::Any.new(2),
      }),
      "errors" => JSON::Any.new([
        {
          "row"   => JSON::Any.new(3),
          "error" => JSON::Any.new("Invalid email format"),
        },
        {
          "row"   => JSON::Any.new(7),
          "error" => JSON::Any.new("Duplicate username"),
        },
      ]),
    }

    respond_with(response_data)
  end

  # Private helper methods

  private def ensure_demo_data
    if Models::User.all.empty?
      Models::User.seed_demo_data
    end
  end

  private def query_params_hash : Hash(String, JSON::Any)
    hash = {} of String => JSON::Any
    request.query_params.each do |key, value|
      # Handle array parameters (e.g., tags[]=foo&tags[]=bar)
      if key.ends_with?("[]")
        actual_key = key[0..-3]
        hash[actual_key] ||= JSON::Any.new([] of JSON::Any)
        if arr = hash[actual_key].as_a?
          arr << JSON::Any.new(value)
        end
      else
        hash[key] = JSON::Any.new(value)
      end
    end
    hash
  end

  private def request_body_hash : Hash(String, JSON::Any)
    begin
      if request.body
        body_string = request.body.not_nil!.gets_to_end
        if !body_string.empty?
          JSON.parse(body_string).as_h
        else
          {} of String => JSON::Any
        end
      else
        {} of String => JSON::Any
      end
    rescue
      {} of String => JSON::Any
    end
  end

  private def sort_users(users : Array(Models::User), sort_by : String, sort_order : String) : Array(Models::User)
    sorted = case sort_by
             when "email"
               users.sort_by(&.email)
             when "username"
               users.sort_by(&.username)
             when "created_at"
               users.sort_by(&.created_at)
             when "updated_at"
               users.sort_by(&.updated_at)
             else
               users
             end

    sort_order == "desc" ? sorted.reverse : sorted
  end
end

# Additional controllers for demonstration

class AuthController < Amber::Controller::Base
  include Amber::Schema::ControllerIntegration

  # POST /auth/login
  def login
    login_schema = Schemas::LoginSchema.new(request_body_hash)
    result = login_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # Simulate authentication
    username_or_email = login_schema.username_or_email
    password = login_schema.password

    # Find user by email or username
    user = Models::User.find_by_email(username_or_email) ||
           Models::User.find_by_username(username_or_email)

    if user && password == "password123" # Obviously not secure!
      # Generate token (simulated)
      token = Base64.encode(Random::Secure.random_bytes(32))

      response_data = {
        "token"      => JSON::Any.new(token),
        "user"       => user.to_h,
        "expires_at" => JSON::Any.new((Time.utc + 24.hours).to_s),
      }

      respond_with(response_data)
    else
      respond_with_error("Invalid credentials", 401, "invalid_credentials")
    end
  end

  # POST /auth/logout
  def logout
    # In real app, would invalidate token
    respond_with({"message" => JSON::Any.new("Logged out successfully")})
  end

  # POST /auth/refresh
  def refresh
    # In real app, would validate and refresh token
    token = Base64.encode(Random::Secure.random_bytes(32))

    respond_with({
      "token"      => JSON::Any.new(token),
      "expires_at" => JSON::Any.new((Time.utc + 24.hours).to_s),
    })
  end

  private def request_body_hash : Hash(String, JSON::Any)
    begin
      if request.body
        body_string = request.body.not_nil!.gets_to_end
        if !body_string.empty?
          JSON.parse(body_string).as_h
        else
          {} of String => JSON::Any
        end
      else
        {} of String => JSON::Any
      end
    rescue
      {} of String => JSON::Any
    end
  end
end

class ContactController < Amber::Controller::Base
  include Amber::Schema::ControllerIntegration

  # POST /contact
  def create
    contact_schema = Schemas::ContactFormSchema.new(form_params_hash)
    result = contact_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # In real app, would send email or save to database
    respond_with({
      "message"          => JSON::Any.new("Thank you for your message. We'll get back to you soon!"),
      "reference_number" => JSON::Any.new("CONTACT-#{Time.utc.to_unix}"),
    })
  end

  private def form_params_hash : Hash(String, JSON::Any)
    hash = {} of String => JSON::Any
    params.to_h.each do |key, value|
      hash[key.to_s] = JSON::Any.new(value.to_s)
    end
    hash
  end
end

class SubscriptionController < Amber::Controller::Base
  include Amber::Schema::ControllerIntegration

  # POST /subscribe
  def create
    subscription_schema = Schemas::SubscriptionSchema.new(form_params_hash)
    result = subscription_schema.validate

    if result.failure?
      return respond_with_errors(result.errors, 422)
    end

    # In real app, would save subscription
    respond_with({
      "message"         => JSON::Any.new("Successfully subscribed to newsletter!"),
      "subscription_id" => JSON::Any.new("SUB-#{Time.utc.to_unix}"),
    }, 201)
  end

  private def form_params_hash : Hash(String, JSON::Any)
    hash = {} of String => JSON::Any
    params.to_h.each do |key, value|
      if key.to_s == "interests"
        # Handle array from form
        hash[key.to_s] = JSON::Any.new(value.to_s.split(",").map { |v| JSON::Any.new(v.strip) })
      else
        hash[key.to_s] = JSON::Any.new(value.to_s)
      end
    end
    hash
  end
end

class HealthController < Amber::Controller::Base
  # GET /health
  def index
    response_data = {
      "status"    => JSON::Any.new("healthy"),
      "version"   => JSON::Any.new("1.0.0"),
      "timestamp" => JSON::Any.new(Time.utc.to_s),
    }

    respond_with(response_data)
  end
end

class HomeController < Amber::Controller::Base
  # GET /
  def index
    response.content_type = "text/html"
    response.print <<-HTML
    <!DOCTYPE html>
    <html>
    <head>
      <title>Amber Schema API Demo</title>
    </head>
    <body>
      <h1>Amber Schema API Demo</h1>
      <p>This is a demonstration of the Amber Schema API.</p>
      <p>Check out the API endpoints at <code>/users</code></p>
    </body>
    </html>
    HTML
    response.close
  end
end
