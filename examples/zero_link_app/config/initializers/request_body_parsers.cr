# XML request bodies are opt-in in Amber V2. This app parses them with Mica,
# a pure-Crystal XML parser, so the binary links no XML library. Mica reads
# a body into the same fields a JSON object gives, so one schema serves both.
require "mica/xml/fields"

{"application/xml", "text/xml"}.each do |media_type|
  Amber::Schema::Parser::ParserRegistry.register_body_parser(media_type) do |body|
    Mica::XML::Fields.read(body)
  end
end
