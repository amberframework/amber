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
    #
    # Text values are measured before they are built (`text_of`), so an
    # over-limit value is rejected without being copied. Each text node is
    # measured once, and each element's measurement is reused by its
    # ancestors.
    class ExtractionAllowance
      EXTRACTED_BYTES_FACTOR = 4

      # The byte size of a run of text, and of the whitespace that
      # `String#strip` would remove from each end.
      private record TextSpan, bytesize : Int64, leading : Int64, trailing : Int64 do
        def self.of(text : String) : TextSpan
          leading = 0_i64
          text.each_char do |char|
            break unless char.whitespace?
            leading += char.bytesize
          end
          size = text.bytesize.to_i64
          return new(size, size, size) if leading == size

          # The text has a character that is not whitespace, so this stops
          # before the start.
          trailing = 0_i64
          reader = Char::Reader.new(at_end: text)
          while reader.current_char.whitespace?
            trailing += reader.current_char.bytesize
            reader.previous_char
          end
          new(size, leading, trailing)
        end

        def blank? : Bool
          leading == bytesize
        end

        def stripped_bytesize : Int64
          blank? ? 0_i64 : bytesize - leading - trailing
        end

        def +(other : TextSpan) : TextSpan
          TextSpan.new(
            bytesize + other.bytesize,
            blank? ? bytesize + other.leading : leading,
            other.blank? ? other.bytesize + trailing : other.trailing
          )
        end
      end

      private EMPTY_SPAN = TextSpan.new(0_i64, 0_i64, 0_i64)

      @budget : Amber::Router::Parsers::ParamBudget
      @limits : Amber::Configuration::ParamsConfig
      @remaining_bytes : Int64
      @spans_by_node : Hash(UInt64, TextSpan)
      @text_by_node : Hash(UInt64, String)

      def initialize(@limits : Amber::Configuration::ParamsConfig = Amber.settings.params)
        @budget = Amber::Router::Parsers::ParamBudget.new(@limits)
        @remaining_bytes = @limits.max_document_body_bytes.to_i64 * EXTRACTED_BYTES_FACTOR
        @spans_by_node = {} of UInt64 => TextSpan
        @text_by_node = {} of UInt64 => String
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

      # Whether *node*'s text, stripped, is empty. Measures without copying.
      def blank_text?(node : XML::Node) : Bool
        span_of(node).blank?
      end

      # Returns *node*'s text and its descendants' text, stripped, as
      # `XML::Node#content.strip` would give it. The stripped size is checked
      # against `max_value_bytes` and charged before the string is built, and
      # the stripped text is written straight into a string of that size, so
      # it is copied once.
      def text_of(node : XML::Node) : String
        span = span_of(node)
        return "" if span.blank?

        stripped_bytesize = span.stripped_bytesize
        max_value_bytes = @limits.max_value_bytes
        if stripped_bytesize > max_value_bytes
          raise Amber::Exceptions::ParameterLimitExceeded.new("max_value_bytes", max_value_bytes)
        end
        charge!(stripped_bytesize)

        capacity = stripped_bytesize.to_i32
        String.new(capacity) do |buffer|
          writer = StrippedTextWriter.new(buffer, capacity, span.leading)
          append_text(node, writer)
          {writer.offset, 0}
        end
      end

      private def span_of(node : XML::Node) : TextSpan
        address = node.to_unsafe.address
        if span = @spans_by_node[address]?
          return span
        end

        span = if text_piece?(node)
                 TextSpan.of(piece_text(node))
               else
                 node.children.reduce(EMPTY_SPAN) do |total, child|
                   text_piece?(child) || child.element? ? total + span_of(child) : total
                 end
               end
        @spans_by_node[address] = span
      end

      # Writes text pieces into a string buffer, dropping the first *skip*
      # bytes (the leading whitespace) and anything past *capacity* (the
      # trailing whitespace).
      private class StrippedTextWriter
        getter offset : Int32 = 0

        def initialize(@buffer : Pointer(UInt8), @capacity : Int32, skip : Int64)
          @skip = skip
        end

        def write(piece : String) : Nil
          bytes = piece.to_slice
          if @skip > 0
            dropped = Math.min(@skip, bytes.size.to_i64).to_i32
            bytes += dropped
            @skip -= dropped
          end
          count = Math.min(bytes.size, @capacity - @offset)
          return if count <= 0

          (@buffer + @offset).copy_from(bytes.to_unsafe, count)
          @offset += count
        end
      end

      private def append_text(node : XML::Node, writer : StrippedTextWriter) : Nil
        if text_piece?(node)
          writer.write(piece_text(node))
          return
        end

        node.children.each do |child|
          if text_piece?(child) || (child.element? && !span_of(child).bytesize.zero?)
            append_text(child, writer)
          end
        end
      end

      # The content of one text piece, read from libxml once and reused, so
      # every ancestor that copies it copies the same string. The cache holds
      # at most the document's own text.
      private def piece_text(node : XML::Node) : String
        @text_by_node[node.to_unsafe.address] ||= node.content
      end

      # Text, CDATA, and entity reference nodes: the pieces
      # `XML::Node#content` joins.
      private def text_piece?(node : XML::Node) : Bool
        node.text? || node.cdata? || node.type.entity_ref_node?
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
      document = parse_document(xml_string, limits)

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

      document = parse_document(xml_string, limits)
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

    # Parses *xml_string* and checks that the document has at most
    # `max_document_nodes` nodes before any field is extracted.
    private def self.parse_document(xml_string : String, limits : Amber::Configuration::ParamsConfig) : XML::Node
      document = XML.parse(xml_string)
      max_nodes = limits.max_document_nodes
      if count_nodes(document, max_nodes) > max_nodes
        raise Amber::Exceptions::ParameterLimitExceeded.new("max_document_nodes", max_nodes)
      end
      document
    end

    # Counts *node* and its attributes and descendants, stopping once the
    # count passes *stop_after*, so the walk is bounded by the limit.
    private def self.count_nodes(node : XML::Node, stop_after : Int32) : Int32
      count = 1
      if node.element?
        count += node.attributes.size
      end
      node.children.each do |child|
        count += count_nodes(child, stop_after - count)
        return count if count > stop_after
      end
      count
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

    # Extract XML element and its children into a hash. An element with
    # child elements reports all of its text, its descendants' included, as
    # `element#text`; *allowance* measures that text once per node and
    # charges every copy, so nesting cannot multiply the output.
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
      text_content = allowance.text_of(element)

      if text_content.empty?
        # Empty element - still add it to the result if it has no children
        unless has_child_elements
          result[element_name] = JSON::Any.new("")
        end
      else
        # Element has content
        if has_child_elements
          text_key = "#{element_name}#text"
          allowance.charge_key!(text_key)
          result[text_key] = JSON::Any.new(text_content)
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
    # checked against `max_value_bytes` and charged to *allowance* before it
    # is copied, so many overlapping matches cannot copy the same text
    # without bound.
    def self.extract_node_value(node : XML::Node, allowance : ExtractionAllowance = ExtractionAllowance.new) : JSON::Any
      content = allowance.text_of(node)

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
        document = parse_document(xml_string, Amber.settings.params)

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

      document = parse_document(xml_string, Amber.settings.params)

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
