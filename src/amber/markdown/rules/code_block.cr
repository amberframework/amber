module Amber::Markdown::Rule
  struct CodeBlock
    include Rule

    # Returns the length of the opening code fence that starts *text*, or
    # `nil`: three or more backticks with no backtick after them on the line,
    # or three or more tildes.
    def self.opening_fence_length(text : String) : Int32?
      fence_size = fence_run_size(text)
      return unless fence_size
      return fence_size if text.byte_at(0) == '~'.ord

      line_end = text.byte_index('\n', fence_size) || text.bytesize
      next_backtick = text.byte_index('`', fence_size)
      fence_size unless next_backtick && next_backtick < line_end
    end

    # Returns the length of the closing code fence that starts *text*, or
    # `nil`: three or more backticks or tildes followed only by spaces, up to
    # the end of the text or a final newline.
    def self.closing_fence_length(text : String) : Int32?
      fence_size = fence_run_size(text)
      return unless fence_size

      index = fence_size
      while index < text.bytesize && text.byte_at(index) == ' '.ord
        index += 1
      end
      at_end = index == text.bytesize || (index == text.bytesize - 1 && text.byte_at(index) == '\n'.ord)
      fence_size if at_end
    end

    # The length of the run of backticks or tildes that starts *text*, when
    # it is at least three long.
    private def self.fence_run_size(text : String) : Int32?
      return if text.empty?
      fence_byte = text.byte_at(0)
      return unless fence_byte == '`'.ord || fence_byte == '~'.ord

      size = 1
      while size < text.bytesize && text.byte_at(size) == fence_byte
        size += 1
      end
      size if size >= 3
    end

    def match(parser : Parser, container : Node) : MatchValue
      line_from_content = parser.line[parser.next_nonspace..-1]
      if !parser.indented && (fence_length = CodeBlock.opening_fence_length(line_from_content))
        # fenced
        parser.close_unmatched_blocks
        node = parser.add_child(Node::Type::CodeBlock, parser.next_nonspace)
        node.fenced = true
        node.fence_length = fence_length
        node.fence_char = line_from_content[0].to_s
        node.fence_offset = parser.indent

        parser.advance_next_nonspace
        parser.advance_offset(fence_length, false)

        MatchValue::Leaf
      elsif parser.indented && !parser.blank && (tip = parser.tip) &&
            !tip.type.paragraph?
        # indented
        parser.advance_offset(Rule::CODE_INDENT, true)
        parser.close_unmatched_blocks
        parser.add_child(Node::Type::CodeBlock, parser.offset)

        MatchValue::Leaf
      else
        MatchValue::None
      end
    end

    def continue(parser : Parser, container : Node) : ContinueStatus
      line = parser.line
      indent = parser.indent
      if container.fenced?
        # fenced
        closing_length = if indent <= 3 && line[parser.next_nonspace]? == container.fence_char[0]
                           CodeBlock.closing_fence_length(line[parser.next_nonspace..-1])
                         end

        if closing_length && closing_length >= container.fence_length
          # closing fence - we're at end of line, so we can return
          parser.token(container, parser.current_line)
          return ContinueStatus::Return
        else
          # skip optional spaces of fence offset
          index = container.fence_offset
          while index > 0 && space_or_tab?(parser.line[parser.offset]?)
            parser.advance_offset(1, true)
            index -= 1
          end
        end
      else
        # indented
        if indent >= Rule::CODE_INDENT
          parser.advance_offset(Rule::CODE_INDENT, true)
        elsif parser.blank
          parser.advance_next_nonspace
        else
          return ContinueStatus::Stop
        end
      end

      ContinueStatus::Continue
    end

    def token(parser : Parser, container : Node) : Nil
      if container.fenced?
        # fenced
        first_line, _, text = container.text.partition('\n')

        container.fence_language = Utils.decode_entities_string(first_line.strip)
        container.text = text
      else
        # indented
        container.text = container.text.gsub(/(\n *)+$/, "\n")
      end
    end

    def can_contain?(type)
      false
    end

    def accepts_lines? : Bool
      true
    end
  end
end
