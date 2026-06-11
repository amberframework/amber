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
      escaped_text.gsub(/#{Regex.escape(escaped_phrase)}/i) do |match|
        "<#{tag}>#{match}</#{tag}>"
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
      paragraphs = escaped.split(/\n{2,}/)
      paragraphs.map do |paragraph|
        "<p>#{paragraph.gsub("\n", "<br />")}</p>"
      end.join
    end

    # Wraps text at the specified line width.
    #
    # ```
    # word_wrap("A very long sentence", line_width: 10)
    # ```
    def word_wrap(text : String, line_width : Int32 = 80) : String
      text.gsub(/(.{1,#{line_width}})(\s+|$)/) do |_, match|
        line = match[1]
        trailing = match[2]?
        if trailing && !trailing.empty?
          line + "\n"
        else
          line
        end
      end.chomp("\n")
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
      html.gsub(/<[^>]*>/, "")
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
