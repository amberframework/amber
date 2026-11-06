require "html"

abstract class ExceptionPage
  # Colors one line of Crystal source for the exception page, using the CSS
  # classes in `exception_page.ecr`: `c` comment, `s` string, `n` number,
  # `t` constant, `k` keyword.
  #
  # Every piece of the line passes through `HTML.escape`, so the result is safe to
  # place in the page as it is. A line that opens a string without closing it colors
  # the rest of the line as that string, which suits a page showing single lines.
  module CodeColoring
    private LIST_OF_KEYWORDS = Set{
      "abstract", "alias", "annotation", "as", "as?", "asm", "begin", "break", "case", "class",
      "def", "do", "else", "elsif", "end", "ensure", "enum", "extend", "false", "for", "fun",
      "if", "in", "include", "instance_sizeof", "is_a?", "lib", "macro", "module", "next", "nil",
      "nil?", "of", "offsetof", "out", "pointerof", "private", "protected", "require", "rescue",
      "responds_to?", "return", "select", "self", "sizeof", "struct", "super", "then", "true",
      "type", "typeof", "uninitialized", "union", "unless", "until", "verbatim", "when", "while",
      "with", "yield",
    }

    def self.highlight(line : String) : String
      String.build do |html|
        bytes = line.to_slice
        position = 0

        while position < bytes.size
          piece_start = position
          char = bytes[position].unsafe_chr

          if char == '#'
            write_span(html, "c", line.byte_slice(piece_start))
            break
          elsif char == '"' || char == '\''
            position = end_of_string(bytes, position)
            write_span(html, "s", line.byte_slice(piece_start, position - piece_start))
          elsif char.ascii_number?
            position = end_of_run(bytes, position) { |next_char| next_char.ascii_alphanumeric? || next_char == '_' || next_char == '.' }
            write_span(html, "n", line.byte_slice(piece_start, position - piece_start))
          elsif char.ascii_letter? || char == '_'
            position = end_of_run(bytes, position) { |next_char| next_char.ascii_alphanumeric? || next_char == '_' }
            position += 1 if position < bytes.size && bytes[position].unsafe_chr.in?('?', '!')

            word = line.byte_slice(piece_start, position - piece_start)
            if char.ascii_uppercase?
              write_span(html, "t", word)
            elsif LIST_OF_KEYWORDS.includes?(word)
              write_span(html, "k", word)
            else
              html << word
            end
          else
            position = end_of_run(bytes, position + 1) { |next_char| !plain_boundary?(next_char) }
            HTML.escape(line.byte_slice(piece_start, position - piece_start), html)
          end
        end
      end
    end

    # A run of punctuation or multibyte text ends where a colored piece can begin.
    private def self.plain_boundary?(char : Char) : Bool
      char.ascii_alphanumeric? || char.in?('_', '#', '"', '\'')
    end

    # The position just past the closing quote, or the end of the line.
    private def self.end_of_string(bytes : Bytes, opening_position : Int32) : Int32
      quote = bytes[opening_position]
      position = opening_position + 1

      while position < bytes.size
        byte = bytes[position]
        position += 1

        if byte === '\\'
          position += 1
        elsif byte == quote
          return position
        end
      end

      bytes.size
    end

    private def self.end_of_run(bytes : Bytes, position : Int32, & : Char -> Bool) : Int32
      while position < bytes.size && yield bytes[position].unsafe_chr
        position += 1
      end

      position
    end

    private def self.write_span(html : String::Builder, css_class : String, text : String) : Nil
      html << %(<span class=") << css_class << %(">)
      HTML.escape(text, html)
      html << "</span>"
    end
  end
end
