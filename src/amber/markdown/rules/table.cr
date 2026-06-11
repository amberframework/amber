module Amber::Markdown::Rule
  struct Table
    include Rule

    # Matches a table separator row: | --- | :---: | ---: |
    # Supports single and multi-column tables
    SEPARATOR = /^\|?(\s*:?-+:?\s*\|)+\s*:?-+:?\s*\|?\s*$|^\|\s*:?-+:?\s*\|\s*$/

    def match(parser : Parser, container : Node) : MatchValue
      # Tables can only appear at the document level or inside block quotes/items,
      # and only when the current tip is a paragraph (the header row is the paragraph text)
      return MatchValue::None if parser.indented
      return MatchValue::None unless container.type.paragraph?

      # The paragraph text is the potential header row
      # The current line is the potential separator row
      line = parser.line[parser.next_nonspace..-1]
      return MatchValue::None unless line.match(SEPARATOR)

      # Get the header text from the paragraph
      header_text = container.text.chomp
      # Header must be a single line (no newlines in it, except trailing)
      return MatchValue::None if header_text.includes?('\n')

      # Parse the separator to get alignments
      alignments = parse_alignments(line)
      return MatchValue::None if alignments.empty?

      # Parse header cells
      header_cells = parse_cells(header_text)
      return MatchValue::None if header_cells.empty?

      # Column count is determined by the separator row
      column_count = alignments.size

      parser.close_unmatched_blocks

      # Create the table node, replacing the paragraph
      table_node = Node.new(Node::Type::Table)
      table_node.source_pos = container.source_pos
      table_node.data["columns"] = column_count

      container.insert_after(table_node)
      container.unlink

      # Create thead
      thead = Node.new(Node::Type::TableHead)
      thead.open = false
      table_node.append_child(thead)

      # Create header row
      header_row = Node.new(Node::Type::TableRow)
      header_row.open = false
      thead.append_child(header_row)

      # Create header cells
      header_cells.each_with_index do |cell_text, i|
        cell = Node.new(Node::Type::TableCell)
        cell.open = false
        cell.text = cell_text.strip
        cell.data["header"] = true
        if i < alignments.size
          cell.data["align"] = alignments[i]
        else
          cell.data["align"] = ""
        end
        header_row.append_child(cell)
      end

      # Pad with empty cells if needed
      (header_cells.size...column_count).each do |i|
        cell = Node.new(Node::Type::TableCell)
        cell.open = false
        cell.text = ""
        cell.data["header"] = true
        cell.data["align"] = alignments[i]
        header_row.append_child(cell)
      end

      # Create tbody (body rows will be added during continue)
      tbody = Node.new(Node::Type::TableBody)
      tbody.open = false
      table_node.append_child(tbody)

      parser.tip = table_node
      parser.advance_offset(parser.line.size - parser.offset, false)

      MatchValue::Leaf
    end

    def continue(parser : Parser, container : Node) : ContinueStatus
      line = parser.line[parser.offset..-1].strip

      # Blank line or non-pipe line ends the table
      if parser.blank || !line.includes?('|')
        return ContinueStatus::Stop
      end

      # Parse this line as a body row
      column_count = container.data["columns"].as(Int32)
      cells = parse_cells(line)

      # Get or find the tbody node
      tbody = container.last_child?
      return ContinueStatus::Stop unless tbody && tbody.type.table_body?

      # Get alignment data from thead
      alignments = [] of String
      if thead = container.first_child?
        if header_row = thead.first_child?
          cell = header_row.first_child?
          while cell
            alignments << (cell.data["align"]?.try(&.as(String)) || "")
            cell = cell.next?
          end
        end
      end

      # Create body row
      row = Node.new(Node::Type::TableRow)
      row.open = false
      tbody.append_child(row)

      cells.each_with_index do |cell_text, i|
        break if i >= column_count
        cell = Node.new(Node::Type::TableCell)
        cell.open = false
        cell.text = cell_text.strip
        cell.data["header"] = false
        if i < alignments.size
          cell.data["align"] = alignments[i]
        else
          cell.data["align"] = ""
        end
        row.append_child(cell)
      end

      # Pad with empty cells if needed
      (cells.size...column_count).each do |i|
        break if i >= column_count
        cell = Node.new(Node::Type::TableCell)
        cell.open = false
        cell.text = ""
        cell.data["header"] = false
        if i < alignments.size
          cell.data["align"] = alignments[i]
        else
          cell.data["align"] = ""
        end
        row.append_child(cell)
      end

      parser.advance_offset(parser.line.size - parser.offset, false)
      ContinueStatus::Continue
    end

    def token(parser : Parser, container : Node) : Nil
      # Remove empty tbody
      if tbody = container.last_child?
        if tbody.type.table_body? && !tbody.first_child?
          tbody.unlink
        end
      end
    end

    def can_contain?(type : Node::Type) : Bool
      false
    end

    def accepts_lines? : Bool
      false
    end

    private def parse_alignments(separator_line : String) : Array(String)
      alignments = [] of String

      # Strip leading/trailing pipes and whitespace
      line = separator_line.strip
      line = line[1..] if line.starts_with?('|')
      line = line[..-2] if line.ends_with?('|')

      line.split('|').each do |col|
        col = col.strip
        next if col.empty? && alignments.empty? # skip empty leading

        left = col.starts_with?(':')
        right = col.ends_with?(':')

        # Must contain at least one dash
        stripped = col.gsub(':', "").strip
        return [] of String unless stripped.each_char.all? { |c| c == '-' } && !stripped.empty?

        if left && right
          alignments << "center"
        elsif right
          alignments << "right"
        elsif left
          alignments << "left"
        else
          alignments << ""
        end
      end

      alignments
    end

    private def parse_cells(line : String) : Array(String)
      cells = [] of String

      # Strip leading/trailing pipes
      stripped = line.strip
      stripped = stripped[1..] if stripped.starts_with?('|')
      stripped = stripped[..-2] if stripped.ends_with?('|')

      # Split on unescaped pipes
      current_cell = String::Builder.new
      i = 0
      while i < stripped.size
        char = stripped[i]
        if char == '\\' && i + 1 < stripped.size && stripped[i + 1] == '|'
          current_cell << '|'
          i += 2
        elsif char == '|'
          cells << current_cell.to_s
          current_cell = String::Builder.new
          i += 1
        else
          current_cell << char
          i += 1
        end
      end
      cells << current_cell.to_s

      cells
    end
  end
end
