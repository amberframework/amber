# XML parser for request bodies with XPath support
require "xml"

module Amber::Schema::Parser
  class XMLParser < Base
    # XPath utility class for namespace-aware queries
    class XPathContext
      getter document : XML::Node
      getter namespaces : Hash(String, String)

      def initialize(@document : XML::Node, @namespaces = {} of String => String)
      end

      # Execute XPath query with namespace support
      def query(xpath : String) : Array(XML::Node)
        # Basic XPath implementation since Crystal's XML doesn't have full XPath
        # This handles simple queries like //element, //element/@attr, etc.

        if xpath.starts_with?("//")
          element_path = xpath[2..]

          # Handle attribute queries like //book/@id
          if element_path.includes?("/@")
            parts = element_path.split("/@")
            element_name = parts[0]
            attr_name = parts[1]

            nodes = find_elements_by_name(element_name)
            return nodes.compact_map do |node|
              if attr = node.attributes[attr_name]?
                # Create a virtual node for the attribute value
                create_text_node(attr.content)
              end
            end
          else
            # Handle namespace prefixes
            if element_path.includes?(":")
              prefix, local_name = element_path.split(":", 2)
              if namespace_uri = @namespaces[prefix]?
                return find_elements_by_namespace(local_name, namespace_uri)
              end
            end

            return find_elements_by_name(element_path)
          end
        else
          # Simple element name without //
          return find_elements_by_name(xpath)
        end
      end

      # Find elements by name recursively
      private def find_elements_by_name(name : String) : Array(XML::Node)
        results = [] of XML::Node
        traverse_for_name(@document, name, results)
        results
      end

      # Find elements by namespace
      private def find_elements_by_namespace(local_name : String, namespace_uri : String) : Array(XML::Node)
        results = [] of XML::Node
        traverse_for_namespace(@document, local_name, namespace_uri, results)
        results
      end

      # Recursively traverse nodes looking for specific name
      private def traverse_for_name(node : XML::Node, target_name : String, results : Array(XML::Node))
        if node.name == target_name
          results << node
        end

        node.children.each do |child|
          traverse_for_name(child, target_name, results)
        end
      end

      # Recursively traverse nodes looking for namespace match
      private def traverse_for_namespace(node : XML::Node, local_name : String, namespace_uri : String, results : Array(XML::Node))
        # For now, just match by local name since Crystal's XML API is limited
        # TODO: Implement proper namespace matching when available
        if node.name.includes?(":")
          # Handle prefixed names like "ns:book"
          if node.name.split(":").last == local_name
            results << node
          end
        elsif node.name == local_name
          results << node
        end

        node.children.each do |child|
          traverse_for_namespace(child, local_name, namespace_uri, results)
        end
      end

      # Create a virtual text node for attribute values
      private def create_text_node(value : String) : XML::Node
        # Create a temporary document to hold the text node
        temp_doc = XML.parse("<temp>#{value}</temp>")
        temp_doc.first_element_child.not_nil!.children.first
      end
    end

    # Instance methods for Parser::Base interface
    def parse(value : JSON::Any) : JSON::Any
      # If it's already JSON::Any, return as-is
      value
    end

    def can_parse?(value : JSON::Any) : Bool
      # Can always attempt to parse any value
      true
    end

    # Class methods for parsing different input types

    # Parse raw XML string into Hash suitable for schema validation
    def self.parse_string(xml_string : String) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if xml_string.empty?

      # Parse XML document
      document = XML.parse(xml_string)

      # Convert to flat structure suitable for schema validation
      extract_default_fields(document)
    rescue ex : XML::Error
      raise SchemaDefinitionError.new("Invalid XML: #{ex.message}")
    end

    # Parse HTTP request body
    def self.parse_request(request : HTTP::Request) : Hash(String, JSON::Any)
      body = request.body.try(&.gets_to_end) || ""
      parse_string(body)
    end

    # Extract fields from XML using schema field definitions with XPath support
    def self.extract_fields_with_schema(xml_string : String, schema : Definition) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if xml_string.empty?

      document = XML.parse(xml_string)
      result = {} of String => JSON::Any

      # Create XPath context
      namespaces = extract_schema_namespaces(schema)
      xpath_context = XPathContext.new(document, namespaces)

      # Process each field definition
      schema.class.fields.each do |field_name, field_def|
        if xpath = field_def.options["xpath"]?.try(&.as_s)
          # Use XPath to extract field value
          value = extract_field_with_xpath(xpath_context, xpath, field_def)
          result[field_name] = value if value
        end
      end

      result
    rescue ex : XML::Error
      raise SchemaDefinitionError.new("Invalid XML: #{ex.message}")
    end

    # Extract default fields from XML document (without schema)
    def self.extract_default_fields(document : XML::Node) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      # Start with root element
      if root = document.first_element_child
        extract_element_to_hash(root, result)
      end

      result
    end

    # Extract XML element and its children into a hash
    private def self.extract_element_to_hash(element : XML::Node, result : Hash(String, JSON::Any), prefix : String = "")
      element_name = prefix.empty? ? element.name : "#{prefix}.#{element.name}"

      # Handle attributes
      element.attributes.each do |attr|
        attr_name = "#{element_name}@#{attr.name}"
        result[attr_name] = JSON::Any.new(attr.content)
      end

      # Handle text content
      text_content = element.content.strip

      # Check if element has children
      has_child_elements = element.children.any? { |child| child.element? }

      if text_content.empty?
        # Empty element - still add it to the result if it has no children
        unless has_child_elements
          result[element_name] = JSON::Any.new("")
        end
      else
        # Element has content
        if has_child_elements
          result["#{element_name}#text"] = JSON::Any.new(text_content)
        else
          result[element_name] = JSON::Any.new(text_content)
        end
      end

      # Handle child elements
      element.children.each do |child|
        next unless child.element?
        extract_element_to_hash(child, result, element_name)
      end
    end

    # Extract namespaces from schema definition
    private def self.extract_schema_namespaces(schema : Definition) : Hash(String, String)
      namespaces = {} of String => String

      schema.class.fields.each do |field_name, field_def|
        if ns_option = field_def.options["namespaces"]?
          case ns_option.raw
          when Hash
            ns_option.as_h.each do |prefix, uri|
              namespaces[prefix] = uri.as_s
            end
          end
        end
      end

      namespaces
    end

    # Extract field value using XPath
    private def self.extract_field_with_xpath(xpath_context : XPathContext, xpath : String, field_def : Definition::FieldDef) : JSON::Any?
      nodes = xpath_context.query(xpath)
      return nil if nodes.empty?

      # Handle different field types
      case field_def.type
      when "Array(String)", "Array(Int32)", "Array(Float32)", "Array(Float64)"
        # Return array of values
        values = nodes.compact_map do |node|
          extract_node_value(node)
        end
        JSON::Any.new(values)
      else
        # Return first matching value
        if first_node = nodes.first?
          extract_node_value(first_node)
        end
      end
    end

    # Extract value from XML node
    def self.extract_node_value(node : XML::Node) : JSON::Any
      content = node.content.strip

      # For now, treat all content as text since Crystal's XML API is limited
      # TODO: Add CDATA handling when API supports it

      # Try to parse as different types
      parse_xml_value(content)
    end

    # Parse XML string value to appropriate JSON type
    def self.parse_xml_value(value : String) : JSON::Any
      # Empty string = empty string (not nil like in form parsing)
      return JSON::Any.new("") if value.empty?

      # Try boolean (XML typically uses true/false, 1/0)
      case value.downcase
      when "true", "1"
        return JSON::Any.new(true)
      when "false", "0"
        return JSON::Any.new(false)
      end

      # Try null/nil
      return JSON::Any.new(nil) if value.downcase == "null" || value.downcase == "nil"

      # Try integer
      if value =~ /^-?\d+$/ && (int_value = value.to_i64?)
        return JSON::Any.new(int_value)
      end

      # Try float
      if value =~ /^-?\d*\.?\d+([eE][+-]?\d+)?$/ && (float_value = value.to_f64?)
        return JSON::Any.new(float_value)
      end

      # Default to string
      JSON::Any.new(value)
    end

    # Validate XML against schema (used for error reporting)
    def self.validate_xml(xml_string : String, schema : Definition) : Array(Error)
      errors = [] of Error

      begin
        document = XML.parse(xml_string)

        # Create XPath context for validation
        namespaces = extract_schema_namespaces(schema)
        xpath_context = XPathContext.new(document, namespaces)

        # Validate each required field
        schema.class.fields.each do |field_name, field_def|
          next unless field_def.required

          if xpath = field_def.options["xpath"]?.try(&.as_s)
            nodes = xpath_context.query(xpath)
            if nodes.empty?
              errors << RequiredFieldError.new(field_name)
            end
          end
        end
      rescue ex : XML::Error
        errors << CustomValidationError.new("", "Invalid XML: #{ex.message}", "xml_parse_error")
      end

      errors
    end

    # Create detailed parse error with context
    def self.create_parse_error(xml_string : String, error : XML::Error) : SchemaDefinitionError
      SchemaDefinitionError.new("Invalid XML: #{error.message}")
    end

    # Extract text content from mixed content (handling CDATA)
    def self.extract_text_content(element : XML::Node) : String
      # Simplified version - just use content method
      element.content.strip
    end

    # Check if element contains only text content (no child elements)
    def self.is_text_only?(element : XML::Node) : Bool
      # Simplified check
      element.children.none? { |child| child.name != "#text" }
    end

    # Handle XML namespace declarations
    def self.extract_namespace_declarations(element : XML::Node) : Hash(String, String)
      namespaces = {} of String => String

      element.attributes.each do |attr|
        if attr.name.starts_with?("xmlns:")
          prefix = attr.name[6..] # Remove "xmlns:" prefix
          namespaces[prefix] = attr.content
        elsif attr.name == "xmlns"
          namespaces[""] = attr.content # Default namespace
        end
      end

      namespaces
    end

    # Parse XML with explicit namespace handling
    def self.parse_with_namespaces(xml_string : String, explicit_namespaces : Hash(String, String) = {} of String => String) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if xml_string.empty?

      document = XML.parse(xml_string)

      # Merge explicit namespaces with those found in document
      all_namespaces = explicit_namespaces.dup
      if root = document.first_element_child
        doc_namespaces = extract_namespace_declarations(root)
        doc_namespaces.each { |prefix, uri| all_namespaces[prefix] = uri }
      end

      # Create xpath context with all namespaces
      xpath_context = XPathContext.new(document, all_namespaces)

      # For now, return default extraction
      # This could be enhanced to use namespace-aware extraction
      extract_default_fields(document)
    rescue ex : XML::Error
      raise SchemaDefinitionError.new("Invalid XML: #{ex.message}")
    end

    # Error handling for malformed XML
    def self.handle_xml_errors(&block)
      yield
    rescue ex : XML::Error
      case ex.message
      when .includes?("mismatched tag")
        raise SchemaDefinitionError.new("XML structure error: Mismatched opening/closing tags")
      when .includes?("not well-formed")
        raise SchemaDefinitionError.new("XML syntax error: Document is not well-formed")
      when .includes?("invalid character")
        raise SchemaDefinitionError.new("XML encoding error: Invalid character in document")
      else
        raise SchemaDefinitionError.new("XML parsing error: #{ex.message}")
      end
    end
  end
end
