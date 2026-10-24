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
    # Text is measured in libxml's own buffers, walking the tree by pointer,
    # before any of it is copied: an over-limit value is rejected without
    # being built, each text node is measured once, and each element's
    # measurement is reused by its ancestors.
    class ExtractionAllowance
      EXTRACTED_BYTES_FACTOR = 4

      # The byte size of a run of text, and of the whitespace that
      # `String#strip` would remove from each end.
      private record TextSpan, bytesize : Int64, leading : Int64, trailing : Int64 do
        def self.of(bytes : Bytes) : TextSpan
          size = bytes.size.to_i64
          leading = leading_whitespace(bytes)
          return new(size, size, size) if leading == size

          new(size, leading, trailing_whitespace(bytes))
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

        # Bytes of whitespace (`Char#whitespace?`) at the start of *bytes*.
        private def self.leading_whitespace(bytes : Bytes) : Int64
          position = 0
          while position < bytes.size
            width = sequence_width(bytes[position])
            break if position + width > bytes.size
            break unless whitespace_at?(bytes, position, width)
            position += width
          end
          position.to_i64
        end

        # Bytes of whitespace at the end of *bytes*, which holds at least one
        # character that is not whitespace.
        private def self.trailing_whitespace(bytes : Bytes) : Int64
          finish = bytes.size
          while finish > 0
            start = finish - 1
            # Step back over UTF-8 continuation bytes to the character's start.
            while start > 0 && finish - start < 4 && (bytes[start] & 0xC0) == 0x80
              start -= 1
            end
            width = finish - start
            break unless sequence_width(bytes[start]) == width && whitespace_at?(bytes, start, width)
            finish = start
          end
          (bytes.size - finish).to_i64
        end

        private def self.sequence_width(lead : UInt8) : Int32
          if lead < 0x80
            1
          elsif lead >= 0xF0
            4
          elsif lead >= 0xE0
            3
          else
            2
          end
        end

        # Decodes the UTF-8 sequence at *position* without allocating and
        # tests it with `Char#whitespace?`.
        private def self.whitespace_at?(bytes : Bytes, position : Int32, width : Int32) : Bool
          lead = bytes[position].to_i32
          return lead.unsafe_chr.whitespace? if width == 1

          codepoint = lead & (0x7F >> width)
          (1...width).each do |offset|
            continuation = bytes[position + offset].to_i32
            return false unless (continuation & 0xC0) == 0x80
            codepoint = (codepoint << 6) | (continuation & 0x3F)
          end
          return false if codepoint > Char::MAX_CODEPOINT || (0xD800..0xDFFF).includes?(codepoint)
          codepoint.unsafe_chr.whitespace?
        end
      end

      private EMPTY_SPAN = TextSpan.new(0_i64, 0_i64, 0_i64)

      @budget : Amber::Router::Parsers::ParamBudget
      @limits : Amber::Configuration::ParamsConfig
      @remaining_bytes : Int64
      @spans_by_node : Hash(UInt64, TextSpan)
      @entity_text_by_node : Hash(UInt64, String)
      @document : XML::Document?

      def initialize(@limits : Amber::Configuration::ParamsConfig = Amber.settings.params)
        @budget = Amber::Router::Parsers::ParamBudget.new(@limits)
        @remaining_bytes = @limits.max_document_body_bytes.to_i64 * EXTRACTED_BYTES_FACTOR
        @spans_by_node = {} of UInt64 => TextSpan
        @entity_text_by_node = {} of UInt64 => String
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

      # Returns *node*'s text and its descendants' text, stripped, as
      # `XML::Node#content.strip` would give it. The stripped size is checked
      # against `max_value_bytes` and charged before the string is built, and
      # the stripped text is written straight into a string of that size, so
      # it is copied once.
      def text_of(node : XML::Node) : String
        @document = node.document
        pointer = node.to_unsafe
        span = span_of(pointer)
        return "" if span.blank?

        stripped_bytesize = span.stripped_bytesize
        check_value_size!(stripped_bytesize)
        charge!(stripped_bytesize)

        capacity = stripped_bytesize.to_i32
        String.new(capacity) do |buffer|
          writer = StrippedTextWriter.new(buffer, capacity, span.leading)
          append_text(pointer, writer)
          {writer.offset, 0}
        end
      end

      # Returns an attribute's value after measuring it in libxml's buffers,
      # checking it against `max_value_bytes`, and charging it.
      def attribute_value(attribute : XML::Node) : String
        @document = attribute.document
        size = 0_i64
        child = attribute.to_unsafe.value.children
        while child
          size += piece_bytes(child).size
          child = child.value.next
        end
        check_value_size!(size)
        charge!(size)
        attribute.content
      end

      private def check_value_size!(size : Int64) : Nil
        max_value_bytes = @limits.max_value_bytes
        return if size <= max_value_bytes

        raise Amber::Exceptions::ParameterLimitExceeded.new("max_value_bytes", max_value_bytes)
      end

      private def span_of(pointer : LibXML::Node*) : TextSpan
        address = pointer.address
        if span = @spans_by_node[address]?
          return span
        end

        span = EMPTY_SPAN
        if text_piece?(pointer)
          span = TextSpan.of(piece_bytes(pointer))
        else
          child = pointer.value.children
          while child
            span += span_of(child) if text_piece?(child) || child.value.type.element_node?
            child = child.value.next
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

        def write(bytes : Bytes) : Nil
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

      private def append_text(pointer : LibXML::Node*, writer : StrippedTextWriter) : Nil
        if text_piece?(pointer)
          writer.write(piece_bytes(pointer))
          return
        end

        child = pointer.value.children
        while child
          if text_piece?(child) || (child.value.type.element_node? && !span_of(child).bytesize.zero?)
            append_text(child, writer)
          end
          child = child.value.next
        end
      end

      # The bytes of one text piece. Text and CDATA are read in place from
      # libxml's buffer; an entity reference's expansion is read once.
      private def piece_bytes(pointer : LibXML::Node*) : Bytes
        type = pointer.value.type
        if type.entity_ref_node?
          document = @document
          return Bytes.empty unless document
          address = pointer.address
          return (@entity_text_by_node[address] ||= XML::Node.new(pointer, document).content).to_slice
        end
        return Bytes.empty unless type.text_node? || type.cdata_section_node?

        content = pointer.value.content
        return Bytes.empty if content.null?
        Bytes.new(content, LibC.strlen(content), read_only: true)
      end

      # Text, CDATA, and entity reference nodes: the pieces
      # `XML::Node#content` joins.
      private def text_piece?(pointer : LibXML::Node*) : Bool
        type = pointer.value.type
        type.text_node? || type.cdata_section_node? || type.entity_ref_node?
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
      body = request.read_document_body
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

    # Parses *xml_string*, holding it to `max_document_nodes` nodes.
    #
    # A well-formed document is counted while it streams, so one with too
    # many nodes is rejected before its tree is built. libxml recovers from
    # malformed markup and the streaming count stops at the first error, so
    # the parsed tree is counted again, by pointer, before any extraction.
    private def self.parse_document(xml_string : String, limits : Amber::Configuration::ParamsConfig) : XML::Node
      max_nodes = limits.max_document_nodes
      if streamed_node_count(xml_string, max_nodes) > max_nodes
        raise Amber::Exceptions::ParameterLimitExceeded.new("max_document_nodes", max_nodes)
      end

      document = XML.parse(xml_string)
      if tree_node_count(document.to_unsafe, max_nodes) > max_nodes
        raise Amber::Exceptions::ParameterLimitExceeded.new("max_document_nodes", max_nodes)
      end
      document
    end

    # :nodoc:
    # Counts the nodes `XML::Reader` streams, with each element's attributes,
    # stopping once the count passes *stop_after* or the markup is
    # malformed.
    def self.streamed_node_count(xml_string : String, stop_after : Int32) : Int32
      reader = XML::Reader.new(xml_string)
      count = 0
      while reader.read
        node_type = reader.node_type
        next if node_type.end_element?
        count += 1
        count += reader.attributes_count if node_type.element?
        return count if count > stop_after
      end
      count
    end

    # Counts the descendants of *pointer*, with each element's attributes,
    # by following libxml's links, stopping once the count passes
    # *stop_after*. Nothing is allocated per node.
    private def self.tree_node_count(pointer : LibXML::Node*, stop_after : Int32) : Int32
      count = 0
      child = pointer.value.children
      while child
        count += 1
        if child.value.type.element_node?
          attribute = child.value.properties
          while attribute
            count += 1
            attribute = attribute.value.next.as(LibXML::Attr*)
          end
          count += tree_node_count(child, stop_after - count)
        end
        return count if count > stop_after
        child = child.value.next
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
        attribute_value = allowance.attribute_value(attr)
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
