# Schema definitions for user-related operations
# Demonstrates various Schema API features

require "../../src/amber/schema"

module Schemas
  # Schema for creating a new user
  class CreateUserSchema < Amber::Schema::Definition
    # Basic fields with validation
    field :email, String, required: true, format: "email"
    field :first_name, String, required: true, min_length: 2, max_length: 50
    field :last_name, String, required: true, min_length: 2, max_length: 50
    field :username, String, required: true, min_length: 3, max_length: 20, pattern: "^[a-zA-Z0-9_]+$"
    field :password, String, required: true, min_length: 8, max_length: 100
    field :password_confirmation, String, required: true

    # Optional fields with validation
    field :age, Int32, min: 13, max: 120
    field :phone, String, pattern: "^\\+?[1-9]\\d{1,14}$" # E.164 format
    field :role, String, enum: ["user", "moderator", "admin"], default: "user"
    field :tags, Array(String), max_length: 10 # Max 10 tags

    # Nested object validation
    nested :address, AddressSchema
    nested :preferences, UserPreferencesSchema

    # Custom validation - passwords must match
    validate do |context|
      password = context.data["password"]?.try(&.as_s)
      confirmation = context.data["password_confirmation"]?.try(&.as_s)

      if password && confirmation && password != confirmation
        context.add_error(Amber::Schema::CustomValidationError.new(
          "password_confirmation",
          "Password confirmation does not match",
          "passwords_mismatch"
        ))
      end
    end

    # Custom validation - unique email
    validate do |context|
      if email = context.data["email"]?.try(&.as_s)
        if Models::User.find_by_email(email)
          context.add_error(Amber::Schema::CustomValidationError.new(
            "email",
            "Email is already taken",
            "email_taken"
          ))
        end
      end
    end

    # Custom validation - unique username
    validate do |context|
      if username = context.data["username"]?.try(&.as_s)
        if Models::User.find_by_username(username)
          context.add_error(Amber::Schema::CustomValidationError.new(
            "username",
            "Username is already taken",
            "username_taken"
          ))
        end
      end
    end
  end

  # Schema for updating a user
  class UpdateUserSchema < Amber::Schema::Definition
    # All fields are optional for updates
    field :email, String, format: "email"
    field :first_name, String, min_length: 2, max_length: 50
    field :last_name, String, min_length: 2, max_length: 50
    field :username, String, min_length: 3, max_length: 20, pattern: "^[a-zA-Z0-9_]+$"
    field :age, Int32, min: 13, max: 120
    field :phone, String, pattern: "^\\+?[1-9]\\d{1,14}$"
    field :role, String, enum: ["user", "moderator", "admin"]
    field :is_active, Bool
    field :tags, Array(String), max_length: 10

    # Nested schemas
    nested :address, AddressSchema
    nested :preferences, UserPreferencesSchema

    # At least one field must be provided
    validate do |context|
      if context.data.empty?
        context.add_error(Amber::Schema::CustomValidationError.new(
          "_base",
          "At least one field must be provided for update",
          "empty_update"
        ))
      end
    end
  end

  # Schema for address validation
  class AddressSchema < Amber::Schema::Definition
    field :street, String, required: true, min_length: 5, max_length: 100
    field :city, String, required: true, min_length: 2, max_length: 50
    field :state, String, required: true, min_length: 2, max_length: 2        # US state code
    field :postal_code, String, required: true, pattern: "^\\d{5}(-\\d{4})?$" # US ZIP code
    field :country, String, default: "US", enum: ["US", "CA", "MX"]
  end

  # Schema for user preferences
  class UserPreferencesSchema < Amber::Schema::Definition
    field :theme, String, enum: ["light", "dark", "auto"], default: "light"
    field :notifications_enabled, Bool, default: true
    field :language, String, enum: ["en", "es", "fr", "de"], default: "en"
    field :timezone, String, default: "UTC"

    # Validate timezone
    validate do |context|
      if tz = context.data["timezone"]?.try(&.as_s)
        begin
          Time::Location.load(tz)
        rescue
          context.add_error(Amber::Schema::CustomValidationError.new(
            "timezone",
            "Invalid timezone",
            "invalid_timezone"
          ))
        end
      end
    end
  end

  # Schema for user search/filtering
  class UserSearchSchema < Amber::Schema::Definition
    # Define query parameters
    from_query do
      field :q, String, max_length: 100 # Search query
      field :role, String, enum: ["user", "moderator", "admin"]
      field :is_active, Bool
      field :tags, Array(String)
      field :page, Int32, min: 1, default: 1
      field :per_page, Int32, min: 1, max: 100, default: 20
      field :sort_by, String, enum: ["created_at", "updated_at", "email", "username"], default: "created_at"
      field :sort_order, String, enum: ["asc", "desc"], default: "desc"
    end
  end

  # Schema for bulk user creation
  class BulkCreateUsersSchema < Amber::Schema::Definition
    field :users, Array(Hash(String, JSON::Any)), required: true, min_length: 1, max_length: 100

    # Validate each user in the array
    validate do |context|
      if users = context.data["users"]?.try(&.as_a)
        users.each_with_index do |user_data, index|
          if user_hash = user_data.as_h?
            # Create a schema instance for each user
            user_schema = CreateUserSchema.new(user_hash)
            result = user_schema.validate

            if result.failure?
              result.errors.each do |error|
                context.add_error(Amber::Schema::CustomValidationError.new(
                  "users[#{index}].#{error.field}",
                  error.message || "Validation failed",
                  error.code
                ))
              end
            end
          else
            context.add_error(Amber::Schema::CustomValidationError.new(
              "users[#{index}]",
              "Must be an object",
              "invalid_type"
            ))
          end
        end
      end
    end
  end

  # Schema for bulk deletion
  class BulkDeleteUsersSchema < Amber::Schema::Definition
    field :ids, Array(Int64), required: true, min_length: 1, max_length: 100
    field :confirm, Bool, required: true

    # Must confirm deletion
    validate do |context|
      if confirm = context.data["confirm"]?.try(&.as_bool)
        unless confirm
          context.add_error(Amber::Schema::CustomValidationError.new(
            "confirm",
            "Deletion must be confirmed",
            "confirmation_required"
          ))
        end
      end
    end

    # Validate that all IDs exist
    validate do |context|
      if ids = context.data["ids"]?.try(&.as_a)
        missing_ids = [] of Int64
        ids.each do |id_value|
          if id = id_value.as_i64?
            unless Models::User.find(id)
              missing_ids << id
            end
          end
        end

        if missing_ids.any?
          context.add_error(Amber::Schema::CustomValidationError.new(
            "ids",
            "Users not found: #{missing_ids.join(", ")}",
            "users_not_found"
          ))
        end
      end
    end
  end

  # Schema for user activation/deactivation
  class UserActivationSchema < Amber::Schema::Definition
    field :reason, String, max_length: 500
    field :notify_user, Bool, default: false

    # Conditional field - if notifying user, email_template is required
    when_field :notify_user, true do
      field :email_template, String, required: true, enum: ["activation", "deactivation", "custom"]
      field :custom_message, String, max_length: 1000
    end

    # If using custom template, custom_message is required
    validate do |context|
      if context.data["email_template"]?.try(&.as_s) == "custom"
        unless context.data["custom_message"]?
          context.add_error(Amber::Schema::CustomValidationError.new(
            "custom_message",
            "Custom message is required when using custom template",
            "custom_message_required"
          ))
        end
      end
    end
  end

  # Schema for authentication
  class LoginSchema < Amber::Schema::Definition
    field :username_or_email, String, required: true
    field :password, String, required: true
    field :remember_me, Bool, default: false
    field :device_id, String, max_length: 100
    field :device_name, String, max_length: 100

    # Require device info if remember_me is true
    when_field :remember_me, true do
      field :device_id, String, required: true
      field :device_name, String, required: true
    end
  end

  # Schema for CSV import
  class UserImportSchema < Amber::Schema::Definition
    # File upload from multipart form
    from_body do
      field :file, String, required: true # Base64 encoded or file path
      field :format, String, enum: ["csv", "json"], default: "csv"
      field :skip_errors, Bool, default: false
      field :dry_run, Bool, default: false
    end

    # Validate file size (simulated)
    validate do |context|
      if file = context.data["file"]?.try(&.as_s)
        # In real app, would check actual file size
        if file.size > 10_000_000 # 10MB limit
          context.add_error(Amber::Schema::CustomValidationError.new(
            "file",
            "File size must be less than 10MB",
            "file_too_large"
          ))
        end
      end
    end
  end

  # Schema for export parameters
  class UserExportSchema < Amber::Schema::Definition
    from_query do
      field :format, String, enum: ["csv", "json", "xml"], default: "json"
      field :fields, Array(String), default: ["id", "email", "username", "created_at"]
      field :include_inactive, Bool, default: false
      field :date_from, String, format: "date"
      field :date_to, String, format: "date"
    end

    # Validate date range
    validate do |context|
      date_from = context.data["date_from"]?.try(&.as_s)
      date_to = context.data["date_to"]?.try(&.as_s)

      if date_from && date_to
        begin
          from = Time.parse(date_from, "%Y-%m-%d", Time::Location::UTC)
          to = Time.parse(date_to, "%Y-%m-%d", Time::Location::UTC)

          if from > to
            context.add_error(Amber::Schema::CustomValidationError.new(
              "date_from",
              "Start date must be before end date",
              "invalid_date_range"
            ))
          end
        rescue
          # Format validation already handles invalid dates
        end
      end
    end
  end

  # Schema for contact form (demonstrates form data handling)
  class ContactFormSchema < Amber::Schema::Definition
    field :name, String, required: true, min_length: 2, max_length: 100
    field :email, String, required: true, format: "email"
    field :subject, String, required: true, min_length: 5, max_length: 200
    field :message, String, required: true, min_length: 10, max_length: 5000
    field :phone, String, pattern: "^\\+?[1-9]\\d{1,14}$"
    field :preferred_contact, String, enum: ["email", "phone"], default: "email"

    # If preferred contact is phone, phone number is required
    when_field :preferred_contact, "phone" do
      field :phone, String, required: true
    end
  end

  # Schema for newsletter subscription
  class SubscriptionSchema < Amber::Schema::Definition
    field :email, String, required: true, format: "email"
    field :name, String, min_length: 2, max_length: 100
    field :interests, Array(String), enum: ["tech", "business", "design", "marketing"]
    field :frequency, String, enum: ["daily", "weekly", "monthly"], default: "weekly"
    field :accept_terms, Bool, required: true

    # Must accept terms
    validate do |context|
      unless context.data["accept_terms"]?.try(&.as_bool)
        context.add_error(Amber::Schema::CustomValidationError.new(
          "accept_terms",
          "You must accept the terms and conditions",
          "terms_not_accepted"
        ))
      end
    end
  end
end
