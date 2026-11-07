require "html"

module Amber::Controller::Helpers
  module TextHelpers
    # Truncates text to a given length and appends an omission string.
    #
    # ```
    # truncate("Hello World", length: 8)                 # => "Hello..."
    # truncate("Hello World", length: 8, omission: ">>") # => "Hello >>"
    # truncate("Hi", length: 10)                         # => "Hi"
    # ```
    def truncate(text : String, length : Int32 = 30, omission : String = "...") : String
      return text if text.size <= length
      stop = length - omission.size
      return omission if stop <= 0
      text[0, stop] + omission
    end

    # Returns the singular or plural form of a word based on count.
    #
    # ```
    # pluralize(1, "person")           # => "1 person"
    # pluralize(2, "person")           # => "2 people"
    # pluralize(2, "person", "people") # => "2 people"
    # pluralize(0, "item")             # => "0 items"
    # ```
    def pluralize(count : Int32, singular : String, plural : String? = nil) : String
      word = count == 1 ? singular : (plural || singular + "s")
      "#{count} #{word}"
    end

    # Wraps occurrences of a phrase in the text with an HTML tag.
    # Both text and phrase are HTML-escaped before processing.
    #
    # ```
    # highlight("Hello World", "World")             # => "Hello <mark>World</mark>"
    # highlight("Hello World", "world")             # => "Hello <mark>World</mark>"
    # highlight("You found it", "found", tag: "em") # => "You <em>found</em> it"
    # ```
    def highlight(text : String, phrase : String, tag : String = "mark") : String
      escaped_text = HTML.escape(text)
      escaped_phrase = HTML.escape(phrase)
      text_chars = escaped_text.chars
      phrase_chars = escaped_phrase.chars
      phrase_size = phrase_chars.size

      String.build(escaped_text.bytesize) do |io|
        if phrase_size == 0
          # An empty phrase marks the empty text around every character.
          text_chars.each { |char| io << '<' << tag << "></" << tag << '>' << char }
          io << '<' << tag << "></" << tag << '>'
        else
          index = 0
          Amber::Support::TextMatching.match_starts_ignoring_case(text_chars, phrase_chars).each do |match_start|
            (index...match_start).each { |offset| io << text_chars[offset] }
            io << '<' << tag << '>'
            (match_start...match_start + phrase_size).each { |offset| io << text_chars[offset] }
            io << "</" << tag << '>'
            index = match_start + phrase_size
          end
          (index...text_chars.size).each { |offset| io << text_chars[offset] }
        end
      end
    end

    # Converts newlines into `<br />` tags and wraps paragraphs in `<p>` tags.
    # Text is HTML-escaped before processing.
    #
    # ```
    # simple_format("Hello\nWorld")   # => "<p>Hello<br />World</p>"
    # simple_format("Para1\n\nPara2") # => "<p>Para1</p><p>Para2</p>"
    # ```
    def simple_format(text : String) : String
      escaped = HTML.escape(text)
      paragraphs = split_on_blank_lines(escaped)
      paragraphs.map do |paragraph|
        "<p>#{paragraph.gsub("\n", "<br />")}</p>"
      end.join
    end

    # Splits *text* at every run of two or more newlines.
    private def split_on_blank_lines(text : String) : Array(String)
      paragraphs = [] of String
      paragraph_start = 0
      offset = 0
      while newline = text.byte_index('\n', offset)
        run_end = newline
        while run_end < text.bytesize && text.byte_at(run_end) == '\n'.ord
          run_end += 1
        end
        if run_end - newline >= 2
          paragraphs << text.byte_slice(paragraph_start, newline - paragraph_start)
          paragraph_start = run_end
        end
        offset = run_end
      end
      paragraphs << text.byte_slice(paragraph_start, text.bytesize - paragraph_start)
      paragraphs
    end

    # Wraps text at the specified line width.
    #
    # Each line takes as many characters as fit in *line_width*, up to the
    # last whitespace run (which becomes one newline) or the end of the text.
    # A word longer than *line_width* stays whole. Raises `ArgumentError` when
    # *line_width* is less than 1.
    #
    # ```
    # word_wrap("A very long sentence", line_width: 10) # => "A very\nlong\nsentence"
    # ```
    def word_wrap(text : String, line_width : Int32 = 80) : String
      raise ArgumentError.new("line_width must be at least 1, got #{line_width}") if line_width < 1

      chars = text.chars
      size = chars.size
      String.build(text.bytesize) do |io|
        position = 0
        while position < size
          if line_end = wrapped_line_end(chars, position, line_width)
            (position...line_end).each { |index| io << chars[index] }
            whitespace_end = line_end
            while whitespace_end < size && Amber::Support::TextMatching.whitespace?(chars[whitespace_end])
              whitespace_end += 1
            end
            io << '\n' if whitespace_end > line_end
            position = whitespace_end
          else
            io << chars[position]
            position += 1
          end
        end
      end.chomp("\n")
    end

    # The end of the longest line from *start*: at most *line_width*
    # characters with no newline among them, followed by whitespace or the
    # end of the text. `nil` when no such line starts at *start*.
    private def wrapped_line_end(chars : Array(Char), start : Int32, line_width : Int32) : Int32?
      size = chars.size
      longest = 0
      while longest < line_width && start + longest < size && chars[start + longest] != '\n'
        longest += 1
      end
      longest.downto(1) do |length|
        line_end = start + length
        return line_end if line_end == size || Amber::Support::TextMatching.whitespace?(chars[line_end])
      end
      nil
    end

    # Strips all HTML tags from the input string.
    # Handles nested tags, malformed HTML, and self-closing tags.
    #
    # ```
    # strip_tags("<p>Hello <b>World</b></p>")     # => "Hello World"
    # strip_tags("<script>alert('xss')</script>") # => "alert('xss')"
    # strip_tags("No tags here")                  # => "No tags here"
    # ```
    def strip_tags(html : String) : String
      Amber::Support::TextMatching.remove_tags(html)
    end

    # Escapes HTML entities in the given text.
    #
    # ```
    # escape_html("<script>alert('xss')</script>")
    # # => "&lt;script&gt;alert(&#39;xss&#39;)&lt;/script&gt;"
    # ```
    def escape_html(text : String) : String
      HTML.escape(text)
    end
  end
end
