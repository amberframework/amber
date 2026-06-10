# Route definitions for Schema API Demo
# Demonstrates various routing patterns with schema validation

Amber::Server.configure do
  routes :api do
    # User CRUD routes with schema validation
    resources "/users", UsersController, except: [:new, :edit] do
      # Nested routes for user relationships
      get "/posts", UsersController, :posts
      post "/activate", UsersController, :activate
      post "/deactivate", UsersController, :deactivate
    end

    # Bulk operations
    post "/users/bulk", UsersController, :bulk_create
    delete "/users/bulk", UsersController, :bulk_delete

    # Search with complex query parameters
    get "/users/search", UsersController, :search

    # Export/Import operations
    get "/users/export", UsersController, :export
    post "/users/import", UsersController, :import

    # Authentication endpoints
    post "/auth/login", AuthController, :login
    post "/auth/logout", AuthController, :logout
    post "/auth/refresh", AuthController, :refresh

    # Health check endpoint
    get "/health", HealthController, :index
  end

  # Web routes with form validation
  routes :web do
    get "/", HomeController, :index

    # Form submission endpoints
    post "/contact", ContactController, :create
    post "/subscribe", SubscriptionController, :create
  end
end
