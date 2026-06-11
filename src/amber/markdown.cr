require "./markdown/html_entities"
require "./markdown/utils"
require "./markdown/node"
require "./markdown/rule"
require "./markdown/options"
require "./markdown/renderer"
require "./markdown/parser"

module Amber
  module Markdown
    def self.to_html(source : String, options = Options.new) : String
      return "" if source.empty?

      document = Parser.parse(source, options)
      renderer = HTMLRenderer.new(options)
      renderer.render(document)
    end

    # Renders markdown to HTML and also generates a table of contents.
    # Returns a named tuple with `:html` and `:toc` keys.
    # The `:toc` value is an HTML string containing a `<ul>` list of headings.
    # The `toc` option on `Options` should be set to `true` for anchor links
    # to be generated in the headings.
    def self.to_html_with_toc(source : String, options = Options.new) : {html: String, toc: String}
      return {html: "", toc: ""} if source.empty?

      document = Parser.parse(source, options)
      renderer = HTMLRenderer.new(options)
      html = renderer.render(document)
      toc = renderer.generate_toc_html

      {html: html, toc: toc}
    end
  end
end
