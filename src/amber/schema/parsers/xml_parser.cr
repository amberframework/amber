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

    # Bounds what extraction copies out of a parsed document, so nesting
    # cannot multiply the output: each key's length and depth, each value's
    # length, and the total bytes of every extracted key and value, which
    # may be at most `EXTRACTED_BYTES_FACTOR` times
    # `max_document_body_bytes`.
    class ExtractionAllowance
      EXTRACTED_BYTES_FACTOR = 4

      @budget : Amber::Router::Parsers::ParamBudget
      @limits : Amber::Configuration::ParamsConfig
      @remaining_bytes : Int64

      def initialize(@limits : Amber::Configuration::ParamsConfig = Amber.settings.params)
        @budget = Amber::Router::Parsers::ParamBudget.new(@limits)
        @remaining_bytes = @limits.max_document_body_bytes.to_i64 * EXTRACTED_BYTES_FACTOR
      end

      # Checks an extracted key's length and depth, and charges its bytes.
      def charge_key!(key : String) : Nil
        @budget.check_key_shape!(key)
        charge!(key.bytesize)
      end

      # Checks an extracted value's length, and charges its bytes.
      def charge_value!(value : String) : Nil
        @budget.check_value!(value)
        charge!(value.bytesize)
      end

      # Charges *bytes* of text before they are copied.
      def charge!(bytes : Int) : Nil
        @remaining_bytes -= bytes
        return if @remaining_bytes >= 0

        raise Amber::Exceptions::ParameterLimitExceeded.new("max_document_body_bytes", @limits.max_document_body_bytes)
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

    # Parse raw XML string into Hash suitable for schema validation.
    # Extraction is bounded by *limits* (see `ExtractionAllowance`).
    def self.parse_string(xml_string : String, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if xml_string.empty?

      # Parse XML document
      document = XML.parse(xml_string)

      # Convert to flat structure suitable for schema validation
      extract_default_fields(document, ExtractionAllowance.new(limits))
    rescue ex : XML::Error
      raise SchemaDefinitionError.new("Invalid XML: #{ex.message}")
    end

    # Parse HTTP request body
    def self.parse_request(request : HTTP::Request) : Hash(String, JSON::Any)
      budget = request.param_budget
      body = budget.read_document(request.body)
      parse_string(body, budget.limits)
    end

    # Extract fields from XML using schema field definitions with XPath support
    def self.extract_fields_with_schema(xml_string : String, schema : Definition, limits : Amber::Configuration::ParamsConfig = Amber.settings.params) : Hash(String, JSON::Any)
      return {} of String => JSON::Any if xml_string.empty?

      document = XML.parse(xml_string)
      result = {} of String => JSON::Any
      allowance = ExtractionAllowance.new(limits)

      # Create XPath context
      namespaces = extract_schema_namespaces(schema)
      xpath_context = XPathContext.new(document, namespaces)

      # Process each field definition
      schema.class.fields.each do |field_name, field_def|
        if xpath = field_def.options["xpath"]?.try(&.as_s)
          # Use XPath to extract field value
          value = extract_field_with_xpath(xpath_context, xpath, field_def, allowance)
          result[field_name] = value if value
        end
      end

      result
    rescue ex : XML::Error
      raise SchemaDefinitionError.new("Invalid XML: #{ex.message}")
    end

    # Extract default fields from XML document (without schema)
    def self.extract_default_fields(document : XML::Node, allowance : ExtractionAllowance = ExtractionAllowance.new) : Hash(String, JSON::Any)
      result = {} of String => JSON::Any

      # Start with root element
      if root = document.first_element_child
        extract_element_to_hash(root, result, allowance)
      end

      result
    end

    # Extract XML element and its children into a hash. Each node's text is
    # read once: an element with child elements contributes only its own
    # (direct) text, so nesting never copies a descendant's text again.
    private def self.extract_element_to_hash(element : XML::Node, result : Hash(String, JSON::Any), allowance : ExtractionAllowance, prefix : String = "")
      element_name = prefix.empty? ? element.name : "#{prefix}.#{element.name}"
      allowance.charge_key!(element_name)

      # Handle attributes
      element.attributes.each do |attr|
        attr_name = "#{element_name}@#{attr.name}"
        allowance.charge_key!(attr_name)
        attribute_value = attr.content
        allowance.charge_value!(attribute_value)
        result[attr_name] = JSON::Any.new(attribute_value)
      end

      # Check if element has children
      has_child_elements = element.children.any? { |child| child.element? }

      # Handle text content
      text_content = has_child_elements ? direct_text(element) : element.content.strip
      allowance.charge_value!(text_content)

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
        extract_element_to_hash(child, result, allowance, element_name)
      end
    end

    # The element's own text and CDATA children, each stripped, joined by
    # single spaces, without the text of its child elements.
    private def self.direct_text(element : XML::Node) : String
      String.build do |io|
        element.children.each do |child|
          next unless child.text? || child.cdata?
          piece = child.content.strip
          next if piece.empty?
          io << ' ' unless io.empty?
          io << piece
        end
      end
    end

    # Appends the text of *node*'s descendants to *io*, charging each piece
    # to *allowance* before copying it.
    private def self.append_descendant_text(node : XML::Node, io : IO, allowance : ExtractionAllowance) : Nil
      node.children.each do |child|
        if child.text? || child.cdata?
          piece = child.content
          allowance.charge!(piece.bytesize)
          io << piece
        elsif child.element?
          append_descendant_text(child, io, allowance)
        end
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
    private def self.extract_field_with_xpath(xpath_context : XPathContext, xpath : String, field_def : Definition::FieldDef, allowance : ExtractionAllowance) : JSON::Any?
      nodes = xpath_context.query(xpath)
      return nil if nodes.empty?

      # Handle different field types
      case field_def.type
      when "Array(String)", "Array(Int32)", "Array(Float32)", "Array(Float64)"
        # Return array of values
        values = nodes.compact_map do |node|
          extract_node_value(node, allowance)
        end
        JSON::Any.new(values)
      else
        # Return first matching value
        if first_node = nodes.first?
          extract_node_value(first_node, allowance)
        end
      end
    end

    # Extract value from XML node: the text of the node and its descendants,
    # charged to *allowance* as it is copied, so many overlapping matches
    # cannot copy the same text without bound.
    def self.extract_node_value(node : XML::Node, allowance : ExtractionAllowance = ExtractionAllowance.new) : JSON::Any
      content = if node.text? || node.cdata?
                  text = node.content
                  allowance.charge!(text.bytesize)
                  text.strip
                else
                  String.build { |io| append_descendant_text(node, io, allowance) }.strip
                end

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
