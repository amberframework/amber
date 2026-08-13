module Amber::Schema
  # Runtime registry produced by the controller schema macros. The entries are
  # immutable schema classes; only request-local Definition instances contain
  # mutable validation state.
  class Registry
    alias Key = Tuple(String, String)
    alias Factory = Proc(Hash(String, JSON::Any), Definition)
    record Entry, schema_class : Definition.class, factory : Factory
    record ResponseEntry,
      schema_class : Definition.class,
      factory : Factory,
      status : Int32,
      description : String

    @@request_schemas = {} of Key => Entry
    @@response_schemas = {} of Key => ResponseEntry

    def self.register_request(controller : String, action : String, schema : T.class) : Bool forall T
      factory = ->(data : Hash(String, JSON::Any)) { schema.new(data).as(Definition) }
      @@request_schemas[{controller, action}] = Entry.new(schema, factory)
      true
    end

    def self.register_response(
      controller : String,
      action : String,
      schema : T.class,
      status : Int32,
      description : String,
    ) : Bool forall T
      factory = ->(data : Hash(String, JSON::Any)) { schema.new(data).as(Definition) }
      @@response_schemas[{controller, action}] = ResponseEntry.new(schema, factory, status, description)
      true
    end

    def self.request_schema(controller : String, action : String) : Entry?
      @@request_schemas[{controller, action}]?
    end

    def self.response_schema(controller : String, action : String) : ResponseEntry?
      @@response_schemas[{controller, action}]?
    end

    def self.request_schemas : Hash(Key, Entry)
      @@request_schemas
    end

    def self.response_schemas : Hash(Key, ResponseEntry)
      @@response_schemas
    end

    def self.clear : Nil
      @@request_schemas.clear
      @@response_schemas.clear
    end
  end
end
