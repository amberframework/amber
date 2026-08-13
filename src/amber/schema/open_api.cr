module Amber::Schema::OpenAPI
  extend self

  def generate(*, title : String, version : String, description : String? = nil, server_url : String? = nil) : String
    root = {
      "openapi"    => JSON::Any.new("3.1.0"),
      "info"       => JSON::Any.new(info(title, version, description)),
      "paths"      => JSON::Any.new(paths),
      "components" => JSON::Any.new({
        "schemas" => JSON::Any.new(components),
      } of String => JSON::Any),
    } of String => JSON::Any
    if server_url
      root["servers"] = JSON::Any.new([
        JSON::Any.new({"url" => JSON::Any.new(server_url)} of String => JSON::Any),
      ])
    end
    root.to_pretty_json
  end

  private def info(title : String, version : String, description : String?)
    result = {
      "title"   => JSON::Any.new(title),
      "version" => JSON::Any.new(version),
    } of String => JSON::Any
    result["description"] = JSON::Any.new(description) if description
    result
  end

  private def paths : Hash(String, JSON::Any)
    result = {} of String => JSON::Any
    RouteRegistry.all.each do |route|
      verb = route[:verb].downcase
      next if verb == "options"
      path = open_api_path(route[:path])
      operations = result[path]?.try(&.as_h) || {} of String => JSON::Any
      operations[verb] = JSON::Any.new(operation(route))
      result[path] = JSON::Any.new(operations)
    end
    result
  end

  private def operation(route) : Hash(String, JSON::Any)
    controller = route[:controller]
    action = route[:action]
    operation = {
      "operationId" => JSON::Any.new(operation_id(controller, action)),
      "responses"   => JSON::Any.new(responses(controller, action)),
    } of String => JSON::Any

    if request = Registry.request_schema(controller, action)
      parameters = parameters_for(request.schema_class)
      operation["parameters"] = JSON::Any.new(parameters) unless parameters.empty?
      if request.schema_class.fields.values.any? { |field| body_source?(field.source) }
        operation["requestBody"] = JSON::Any.new(request_body(request.schema_class))
      end
    end
    operation
  end

  private def responses(controller : String, action : String)
    success_content = {} of String => JSON::Any
    if response = Registry.response_schema(controller, action)
      schema_ref = JSON::Any.new({"$ref" => JSON::Any.new(schema_reference(response.schema_class))} of String => JSON::Any)
      content_types_for(response.schema_class).each do |content_type|
        success_content[content_type] = JSON::Any.new(media_schema(content_type, schema_ref))
      end
    end

    success_status = response.try(&.status) || 200
    success_description = response.try(&.description) || "Successful response"
    success = {"description" => JSON::Any.new(success_description)} of String => JSON::Any
    success["content"] = JSON::Any.new(success_content) unless success_content.empty?
    {
      success_status.to_s => JSON::Any.new(success),
      "400"               => JSON::Any.new({"description" => JSON::Any.new("Malformed request body")} of String => JSON::Any),
      "415"               => JSON::Any.new({"description" => JSON::Any.new("Request media type is not declared by the schema")} of String => JSON::Any),
      "422"               => JSON::Any.new({"description" => JSON::Any.new("Request schema validation failed")} of String => JSON::Any),
      "500"               => JSON::Any.new({"description" => JSON::Any.new("Declared response schema was not satisfied")} of String => JSON::Any),
    } of String => JSON::Any
  end

  private def request_body(schema_class : Definition.class)
    schema_ref = JSON::Any.new({"$ref" => JSON::Any.new(request_body_schema_reference(schema_class))} of String => JSON::Any)
    content = {} of String => JSON::Any
    content_types_for(schema_class).each do |content_type|
      content[content_type] = JSON::Any.new(media_schema(content_type, schema_ref))
    end
    {
      "required" => JSON::Any.new(schema_class.required_fields.any? do |field_name|
        body_source?(schema_class.fields[field_name].source)
      end),
      "content" => JSON::Any.new(content),
    } of String => JSON::Any
  end

  private def media_schema(content_type : String, schema_ref : JSON::Any)
    schema = if content_type == "application/cose"
               JSON::Any.new({
                 "type"        => JSON::Any.new("string"),
                 "format"      => JSON::Any.new("binary"),
                 "description" => JSON::Any.new("COSE Encrypt0 containing the declared CBOR schema"),
               } of String => JSON::Any)
             else
               schema_ref
             end
    {"schema" => schema} of String => JSON::Any
  end

  private def parameters_for(schema_class : Definition.class) : Array(JSON::Any)
    schema_class.fields.values.compact_map do |field|
      location = parameter_location(field.source)
      next unless location
      parameter = {
        "name"     => JSON::Any.new(field.options["source_name"]?.try(&.as_s?) || field.name),
        "in"       => JSON::Any.new(location),
        "required" => JSON::Any.new(field.required || location == "path"),
        "schema"   => JSON::Any.new(json_schema_for(field)),
      } of String => JSON::Any
      JSON::Any.new(parameter)
    end
  end

  private def parameter_location(source : ParamSource) : String?
    case source
    when .path?   then "path"
    when .query?  then "query"
    when .header? then "header"
    when .cookie? then "cookie"
    else               nil
    end
  end

  private def components : Hash(String, JSON::Any)
    result = {} of String => JSON::Any
    Registry.request_schemas.each_value do |entry|
      if entry.schema_class.fields.values.any? { |field| body_source?(field.source) }
        add_component(result, entry.schema_class, request_body: true)
      end
    end
    Registry.response_schemas.each_value do |entry|
      add_component(result, entry.schema_class)
    end
    result
  end

  private def add_component(
    result : Hash(String, JSON::Any),
    schema_class : Definition.class,
    request_body : Bool = false,
  ) : Nil
    name = request_body ? request_body_component_name(schema_class) : component_name(schema_class)
    return if result.has_key?(name)
    # Reserve the component name before following nested references so a
    # recursive schema cannot recurse forever during document generation.
    result[name] = JSON::Any.new({} of String => JSON::Any)
    properties = {} of String => JSON::Any
    schema_class.fields.each do |field_name, field|
      next if request_body && !body_source?(field.source)
      properties[field_name] = JSON::Any.new(component_schema_for(result, schema_class, field))
    end
    schema = {
      "type"                 => JSON::Any.new("object"),
      "properties"           => JSON::Any.new(properties),
      "additionalProperties" => JSON::Any.new(schema_class.additional_properties?),
    } of String => JSON::Any
    required = schema_class.required_fields.select do |field_name|
      !request_body || body_source?(schema_class.fields[field_name].source)
    end
    schema["required"] = JSON::Any.new(required.map { |name| JSON::Any.new(name) }) unless required.empty?
    add_relationships(schema, schema_class, request_body)
    result[name] = JSON::Any.new(schema)
  end

  private def component_schema_for(
    result : Hash(String, JSON::Any),
    schema_class : Definition.class,
    field : Definition::FieldDef,
  ) : Hash(String, JSON::Any)
    if nested = schema_class.nested_schemas[field.name]?
      add_component(result, nested)
      {"$ref" => JSON::Any.new(schema_reference(nested))}
    elsif nested = schema_class.nested_array_schemas[field.name]?
      add_component(result, nested)
      {
        "type"  => JSON::Any.new("array"),
        "items" => JSON::Any.new({"$ref" => JSON::Any.new(schema_reference(nested))} of String => JSON::Any),
      }
    else
      json_schema_for(field)
    end
  end

  private def add_relationships(
    schema : Hash(String, JSON::Any),
    schema_class : Definition.class,
    request_body : Bool,
  ) : Nil
    included = schema_class.fields.select do |_name, field|
      !request_body || body_source?(field.source)
    end.keys

    dependent_required = {} of String => JSON::Any
    schema_class.requires_together_groups.each do |group|
      fields = group.select { |field| included.includes?(field) }
      next unless fields.size == group.size
      fields.each do |field|
        dependencies = fields.reject { |candidate| candidate == field }
        dependent_required[field] = JSON::Any.new(dependencies.map { |name| JSON::Any.new(name) })
      end
    end
    schema["dependentRequired"] = JSON::Any.new(dependent_required) unless dependent_required.empty?

    all_of = [] of JSON::Any
    schema_class.conditional_groups.each do |group|
      next unless included.includes?(group.condition_field)
      required = group.required_fields.select { |field| included.includes?(field) }
      next if required.empty?

      condition = if group.condition_value.as_s? == "__present__"
                    {
                      "required" => JSON::Any.new([JSON::Any.new(group.condition_field)]),
                    } of String => JSON::Any
                  else
                    {
                      "properties" => JSON::Any.new({
                        group.condition_field => JSON::Any.new({"const" => group.condition_value} of String => JSON::Any),
                      } of String => JSON::Any),
                      "required" => JSON::Any.new([JSON::Any.new(group.condition_field)]),
                    } of String => JSON::Any
                  end
      all_of << JSON::Any.new({
        "if"   => JSON::Any.new(condition),
        "then" => JSON::Any.new({
          "required" => JSON::Any.new(required.map { |name| JSON::Any.new(name) }),
        } of String => JSON::Any),
      } of String => JSON::Any)
    end

    schema_class.requires_one_of_groups.each do |group|
      fields = group.select { |field| included.includes?(field) }
      next unless fields.size == group.size
      alternatives = fields.map do |field|
        JSON::Any.new({
          "required" => JSON::Any.new([JSON::Any.new(field)]),
        } of String => JSON::Any)
      end
      all_of << JSON::Any.new({"oneOf" => JSON::Any.new(alternatives)} of String => JSON::Any)
    end
    schema["allOf"] = JSON::Any.new(all_of) unless all_of.empty?
  end

  private def json_schema_for(field : Definition::FieldDef) : Hash(String, JSON::Any)
    schema = type_schema(field.type)
    options = field.options
    schema["default"] = field.default.not_nil! if field.default
    schema["description"] = options["description"] if options["description"]?
    schema["minimum"] = options["min"] if options["min"]?
    schema["maximum"] = options["max"] if options["max"]?
    schema["minLength"] = options["min_length"] if options["min_length"]?
    schema["maxLength"] = options["max_length"] if options["max_length"]?
    schema["pattern"] = options["pattern"] if options["pattern"]?
    schema["enum"] = options["enum"] if options["enum"]?
    if format = options["format"]?
      schema["format"] = format
    end
    schema
  end

  private def type_schema(type : String) : Hash(String, JSON::Any)
    case type
    when "String"  then {"type" => JSON::Any.new("string")}
    when "Int32"   then {"type" => JSON::Any.new("integer"), "format" => JSON::Any.new("int32")}
    when "Int64"   then {"type" => JSON::Any.new("integer"), "format" => JSON::Any.new("int64")}
    when "Float32" then {"type" => JSON::Any.new("number"), "format" => JSON::Any.new("float")}
    when "Float64" then {"type" => JSON::Any.new("number"), "format" => JSON::Any.new("double")}
    when "Bool"    then {"type" => JSON::Any.new("boolean")}
    when "Time"    then {"type" => JSON::Any.new("string"), "format" => JSON::Any.new("date-time")}
    when "UUID"    then {"type" => JSON::Any.new("string"), "format" => JSON::Any.new("uuid")}
    else
      if match = type.match(/^Array\((.+)\)$/)
        {"type" => JSON::Any.new("array"), "items" => JSON::Any.new(type_schema(match[1]))}
      else
        {"type" => JSON::Any.new("object")}
      end
    end
  end

  private def content_types_for(schema_class : Definition.class) : Array(String)
    content_types = schema_class.content_types
    content_types.empty? ? ["application/json"] : content_types
  end

  private def body_source?(source : ParamSource) : Bool
    source.body? || source.form? || source.multipart?
  end

  private def component_name(schema_class : Definition.class) : String
    schema_class.name.gsub("::", "_")
  end

  private def schema_reference(schema_class : Definition.class) : String
    "#/components/schemas/#{component_name(schema_class)}"
  end

  private def request_body_component_name(schema_class : Definition.class) : String
    "#{component_name(schema_class)}RequestBody"
  end

  private def request_body_schema_reference(schema_class : Definition.class) : String
    "#/components/schemas/#{request_body_component_name(schema_class)}"
  end

  private def operation_id(controller : String, action : String) : String
    "#{controller.gsub("::", "_")}_#{action}"
  end

  private def open_api_path(path : String) : String
    path.gsub(/:([A-Za-z_][A-Za-z0-9_]*)/, "{\\1}")
  end
end
