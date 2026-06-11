require "../../markdown"

module Amber::Controller::Helpers
  module MarkdownHelper
    # Renders a markdown string to HTML.
    #
    # ```
    # render_markdown("# Hello")
    # # => "<h1>Hello</h1>\n"
    #
    # render_markdown("**bold**")
    # # => "<p><strong>bold</strong></p>\n"
    # ```
    def render_markdown(source : String, options : Amber::Markdown::Options = Amber::Markdown::Options.new) : String
      Amber::Markdown.to_html(source, options)
    end

    # Renders a markdown file to HTML.
    #
    # ```
    # render_markdown(file: "README.md")
    # ```
    def render_markdown(*, file : String, options : Amber::Markdown::Options = Amber::Markdown::Options.new) : String
      source = File.read(file)
      Amber::Markdown.to_html(source, options)
    end
  end
end
