module Amber::Mica::Core
  # Characters of input quoted in an error message.
  EXCERPT_CHARS = 120

  # Characters of caller-supplied context (which may itself hold an
  # excerpt) appended to a budget or deadline message.
  CONTEXT_CHARS = 2 * EXCERPT_CHARS + 40

  # Returns *text* cut to its first *limit* characters (with "..." when
  # cut), so an error message stays short however long the input is.
  # Steps over at most *limit* characters.
  def self.excerpt(text : String, limit : Int32 = EXCERPT_CHARS) : String
    reader = Char::Reader.new(text)
    count = 0
    while reader.has_next? && count < limit
      reader.next_char
      count += 1
    end
    reader.has_next? ? "#{text.byte_slice(0, reader.pos)}..." : text
  end

  # Returns the first `EXCERPT_CHARS` characters of *bytes* as a string,
  # like `excerpt`, without copying the rest.
  def self.excerpt(bytes : Bytes) : String
    window = bytes[0, Math.min(bytes.size, EXCERPT_CHARS * 4)]
    text = excerpt(String.new(window))
    window.size < bytes.size && !text.ends_with?("...") ? "#{text}..." : text
  end

  # Returns `excerpt` of *text*, quoted.
  def self.quote(text : String | Bytes) : String
    excerpt(text).inspect
  end
end
