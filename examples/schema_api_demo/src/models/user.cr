# Simple User model for demonstration
# In a real application, this would likely use Granite ORM

module Models
  class User
    include JSON::Serializable

    property id : Int64
    property email : String
    property first_name : String
    property last_name : String
    property username : String
    property age : Int32?
    property phone : String?
    property address : Address?
    property role : String
    property is_active : Bool
    property preferences : UserPreferences?
    property tags : Array(String)
    property created_at : Time
    property updated_at : Time

    # Nested address structure
    struct Address
      include JSON::Serializable

      property street : String
      property city : String
      property state : String
      property postal_code : String
      property country : String

      def initialize(@street : String, @city : String, @state : String, @postal_code : String, @country : String = "US")
      end
    end

    # User preferences
    struct UserPreferences
      include JSON::Serializable

      property theme : String
      property notifications_enabled : Bool
      property language : String
      property timezone : String

      def initialize(@theme = "light", @notifications_enabled = true, @language = "en", @timezone = "UTC")
      end
    end

    # Constructor
    def initialize(@id : Int64, @email : String, @first_name : String, @last_name : String, @username : String,
                   @role : String = "user", @is_active : Bool = true, @age : Int32? = nil,
                   @phone : String? = nil, @address : Address? = nil, @preferences : UserPreferences? = nil,
                   @tags : Array(String) = [] of String)
      @created_at = Time.utc
      @updated_at = Time.utc
    end

    # Class methods for demo purposes
    @@users = [] of User
    @@next_id = 1_i64

    def self.all : Array(User)
      @@users
    end

    def self.find(id : Int64) : User?
      @@users.find { |u| u.id == id }
    end

    def self.find!(id : Int64) : User
      find(id) || raise "User not found"
    end

    def self.find_by_email(email : String) : User?
      @@users.find { |u| u.email == email }
    end

    def self.find_by_username(username : String) : User?
      @@users.find { |u| u.username == username }
    end

    def self.create(params : Hash(String, JSON::Any)) : User
      user = User.new(
        id: @@next_id,
        email: params["email"].as_s,
        first_name: params["first_name"].as_s,
        last_name: params["last_name"].as_s,
        username: params["username"].as_s,
        role: params["role"]?.try(&.as_s) || "user",
        is_active: params["is_active"]?.try(&.as_bool) || true,
        age: params["age"]?.try(&.as_i),
        phone: params["phone"]?.try(&.as_s),
        tags: params["tags"]?.try(&.as_a.map(&.as_s)) || [] of String
      )

      # Handle nested address
      if address_data = params["address"]?.try(&.as_h)
        user.address = Address.new(
          street: address_data["street"].as_s,
          city: address_data["city"].as_s,
          state: address_data["state"].as_s,
          postal_code: address_data["postal_code"].as_s,
          country: address_data["country"]?.try(&.as_s) || "US"
        )
      end

      # Handle preferences
      if prefs_data = params["preferences"]?.try(&.as_h)
        user.preferences = UserPreferences.new(
          theme: prefs_data["theme"]?.try(&.as_s) || "light",
          notifications_enabled: prefs_data["notifications_enabled"]?.try(&.as_bool) || true,
          language: prefs_data["language"]?.try(&.as_s) || "en",
          timezone: prefs_data["timezone"]?.try(&.as_s) || "UTC"
        )
      end

      @@users << user
      @@next_id += 1
      user
    end

    def update(params : Hash(String, JSON::Any)) : User
      @email = params["email"].as_s if params.has_key?("email")
      @first_name = params["first_name"].as_s if params.has_key?("first_name")
      @last_name = params["last_name"].as_s if params.has_key?("last_name")
      @username = params["username"].as_s if params.has_key?("username")
      @role = params["role"].as_s if params.has_key?("role")
      @is_active = params["is_active"].as_bool if params.has_key?("is_active")
      @age = params["age"]?.try(&.as_i) if params.has_key?("age")
      @phone = params["phone"]?.try(&.as_s) if params.has_key?("phone")
      @tags = params["tags"].as_a.map(&.as_s) if params.has_key?("tags")
      @updated_at = Time.utc
      self
    end

    def destroy
      @@users.delete(self)
    end

    def self.destroy_all
      @@users.clear
    end

    def self.search(query : String? = nil, role : String? = nil, is_active : Bool? = nil, tags : Array(String)? = nil) : Array(User)
      results = @@users

      if query
        results = results.select do |user|
          user.email.includes?(query) ||
            user.username.includes?(query) ||
            user.first_name.includes?(query) ||
            user.last_name.includes?(query)
        end
      end

      if role
        results = results.select { |u| u.role == role }
      end

      if is_active != nil
        results = results.select { |u| u.is_active == is_active }
      end

      if tags && !tags.empty?
        results = results.select { |u| (u.tags & tags).any? }
      end

      results
    end

    # Seed some demo data
    def self.seed_demo_data
      destroy_all

      create({
        "email"      => JSON::Any.new("john.doe@example.com"),
        "first_name" => JSON::Any.new("John"),
        "last_name"  => JSON::Any.new("Doe"),
        "username"   => JSON::Any.new("johndoe"),
        "age"        => JSON::Any.new(30),
        "phone"      => JSON::Any.new("+1-555-0123"),
        "role"       => JSON::Any.new("admin"),
        "tags"       => JSON::Any.new(["vip", "early-adopter"]),
        "address"    => JSON::Any.new({
          "street"      => JSON::Any.new("123 Main St"),
          "city"        => JSON::Any.new("San Francisco"),
          "state"       => JSON::Any.new("CA"),
          "postal_code" => JSON::Any.new("94105"),
        }),
      })

      create({
        "email"      => JSON::Any.new("jane.smith@example.com"),
        "first_name" => JSON::Any.new("Jane"),
        "last_name"  => JSON::Any.new("Smith"),
        "username"   => JSON::Any.new("janesmith"),
        "age"        => JSON::Any.new(25),
        "role"       => JSON::Any.new("user"),
        "tags"       => JSON::Any.new(["beta-tester"]),
      })

      create({
        "email"      => JSON::Any.new("bob.wilson@example.com"),
        "first_name" => JSON::Any.new("Bob"),
        "last_name"  => JSON::Any.new("Wilson"),
        "username"   => JSON::Any.new("bobwilson"),
        "role"       => JSON::Any.new("moderator"),
        "is_active"  => JSON::Any.new(false),
        "tags"       => JSON::Any.new(["inactive"]),
      })
    end

    # Helper methods
    def full_name
      "#{first_name} #{last_name}"
    end

    def activate!
      @is_active = true
      @updated_at = Time.utc
    end

    def deactivate!
      @is_active = false
      @updated_at = Time.utc
    end

    # Convert to JSON-compatible hash
    def to_h
      {
        "id"          => JSON::Any.new(id),
        "email"       => JSON::Any.new(email),
        "first_name"  => JSON::Any.new(first_name),
        "last_name"   => JSON::Any.new(last_name),
        "username"    => JSON::Any.new(username),
        "age"         => age ? JSON::Any.new(age.not_nil!) : JSON::Any.new(nil),
        "phone"       => phone ? JSON::Any.new(phone.not_nil!) : JSON::Any.new(nil),
        "address"     => address ? JSON::Any.new(address_to_h(address.not_nil!)) : JSON::Any.new(nil),
        "role"        => JSON::Any.new(role),
        "is_active"   => JSON::Any.new(is_active),
        "preferences" => preferences ? JSON::Any.new(preferences_to_h(preferences.not_nil!)) : JSON::Any.new(nil),
        "tags"        => JSON::Any.new(tags),
        "created_at"  => JSON::Any.new(created_at.to_s),
        "updated_at"  => JSON::Any.new(updated_at.to_s),
      }
    end

    private def address_to_h(addr : Address)
      {
        "street"      => JSON::Any.new(addr.street),
        "city"        => JSON::Any.new(addr.city),
        "state"       => JSON::Any.new(addr.state),
        "postal_code" => JSON::Any.new(addr.postal_code),
        "country"     => JSON::Any.new(addr.country),
      }
    end

    private def preferences_to_h(prefs : UserPreferences)
      {
        "theme"                 => JSON::Any.new(prefs.theme),
        "notifications_enabled" => JSON::Any.new(prefs.notifications_enabled),
        "language"              => JSON::Any.new(prefs.language),
        "timezone"              => JSON::Any.new(prefs.timezone),
      }
    end
  end
end
