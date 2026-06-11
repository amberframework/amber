# Migration Guide: From Amber::Validators to Schema API
#
# This guide helps you migrate from the old params validation system
# to the new Schema API. The Schema API provides more powerful validation,
# type coercion, and API documentation capabilities.
#
# ## Quick Start
#
# The Schema API is automatically included in all Amber controllers.
# You can start using it immediately without breaking existing code.
#
# ## Basic Migration Examples
#
# ### Old Way (Amber::Validators)
# ```
# class UsersController < Amber::Controller::Base
#   def create
#     validation = params.validation do
#       required(:email) { |p| p.email? }
#       required(:password) { |p| p.size >= 8 }
#       optional(:name)
#     end
#
#     unless validation.valid?
#       response.status_code = 400
#       response.print({errors: validation.errors}.to_json)
#       return
#     end
#
#     user = User.create!(
#       email: params[:email],
#       password: params[:password],
#       name: params[:name]?
#     )
#
#     response.print({id: user.id}.to_json)
#   end
# end
# ```
#
# ### New Way (Schema API - Programmatic)
# ```
# class UsersController < Amber::Controller::Base
#   schema :create do
#     field :email, String, required: true
#     field :password, String, required: true
#     field :name, String, required: false
#
#     validate :email, format: "email"
#     validate :password, min_length: 8
#   end
#
#   validate_schema :create
#
#   def create
#     # Data is already validated and available in request_data
#     data = request_data.not_nil!
#
#     user = User.create!(
#       email: data["email"].as_s,
#       password: data["password"].as_s,
#       name: data["name"]?.try(&.as_s)
#     )
#
#     respond_with({
#       "id" => user.id,
#     }, status: 201)
#   end
# end
# ```
#
# ### New Way (Schema API - Annotations)
# ```
# class CreateUserSchema < Amber::Schema::RequestSchema
#   def initialize(name : String)
#     super(name)
#     field :email, String, required: true
#     field :password, String, required: true
#     field :name, String
#
#     validate :email, format: "email"
#     validate :password, min_length: 8
#   end
# end
#
# class UsersController < Amber::Controller::Base
#   auto_validate # Enable annotation processing
#
#   @[Request(schema: CreateUserSchema)]
#   @[Response(status: 201, description: "User created")]
#   def create
#     data = request_data.not_nil!
#
#     user = User.create!(
#       email: data["email"].as_s,
#       password: data["password"].as_s,
#       name: data["name"]?.try(&.as_s)
#     )
#
#     respond_with({"id" => user.id}, status: 201)
#   end
# end
# ```
#
# ## Key Differences
#
# 1. **Validation Location**:
#    - Old: Inside action methods
#    - New: Defined at class level or in separate schema classes
#
# 2. **Data Access**:
#    - Old: `params[:key]` returns String?
#    - New: `request_data["key"]` returns JSON::Any with proper types
#
# 3. **Error Handling**:
#    - Old: Manual error response
#    - New: Automatic 422 response with structured errors
#
# 4. **Type Safety**:
#    - Old: All params are strings
#    - New: Automatic type coercion and validation
#
# ## Backward Compatibility
#
# The old `params` method still works! It now returns a wrapper that:
# - Prioritizes validated schema data when available
# - Falls back to raw params for unvalidated fields
# - Maintains the same interface for existing code
#
# You can access the original params behavior with:
# - `legacy_params` - Original Amber::Validators::Params
# - `raw_params` - Direct access to context.params
#
# ## Advanced Features
#
# ### Combining Multiple Data Sources
# ```
# @[Request(schema: UpdatePostSchema)]
# @[PathParam(name: "id", type: "Int32")]
# @[QueryParam(name: "preview", type: "Bool", default: false)]
# def update
#   # All data sources are merged in request_data
#   post_id = request_data["id"].as_i
#   preview = request_data["preview"].as_bool
#   title = request_data["title"].as_s
# end
# ```
#
# ### Custom Validation Messages
# ```
# schema :create do
#   field :age, Int32, required: true
#   validate :age, min: 18, message: "Must be 18 or older"
# end
# ```
#
# ### Response Validation
# ```
# response_schema :show do
#   field :id, Int32, required: true
#   field :email, String, required: true
#   field :created_at, String, required: true
# end
#
# def show
#   user = User.find(params[:id])
#
#   # Automatically validates response structure
#   respond_with({
#     "id"         => user.id,
#     "email"      => user.email,
#     "created_at" => user.created_at.to_s,
#   })
# end
# ```
#
# ### Content Type Support
# ```
# @[Request(schema: UploadSchema, content_type: "multipart/form-data")]
# def upload
#   # Handle file uploads with validation
# end
# ```
#
# ## Migration Checklist
#
# 1. ✓ Existing controllers continue to work without changes
# 2. ✓ Start with new controllers/actions using Schema API
# 3. ✓ Gradually migrate existing validations as needed
# 4. ✓ Use `auto_validate` for annotation-based validation
# 5. ✓ Define reusable schema classes for complex validations
# 6. ✓ Add response schemas for API consistency
# 7. ✓ Generate OpenAPI documentation from annotations
#
# ## Common Patterns
#
# ### Optional Fields with Defaults
# ```
# schema :search do
#   field :query, String, required: true
#   field :page, Int32, default: 1
#   field :per_page, Int32, default: 20
#
#   validate :page, min: 1
#   validate :per_page, min: 1, max: 100
# end
# ```
#
# ### Nested Objects
# ```
# schema :create_order do
#   field :customer_email, String, required: true
#   field :items, Array(JSON::Any), required: true
#
#   validate :customer_email, format: "email"
#   validate :items, min_items: 1
# end
# ```
#
# ### Conditional Validation
# ```
# schema :update_user do
#   field :email, String
#   field :password, String
#   field :password_confirmation, String
#
#   # Only validate confirmation if password is provided
#   validate :password_confirmation,
#     equals_field: "password",
#     when: ->(data : Hash(String, JSON::Any)) { data.has_key?("password") }
# end
# ```
#
# ## Getting Help
#
# - Check the examples in `src/amber/schema/examples/`
# - Read the annotation documentation in `src/amber/schema/annotations.cr`
# - See the full controller integration example
#
# The Schema API is designed to be intuitive and powerful while maintaining
# backward compatibility with existing Amber applications.
