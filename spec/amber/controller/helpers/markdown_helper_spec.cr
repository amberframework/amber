require "../../../spec_helper"

module Amber::Controller::Helpers
  describe MarkdownHelper do
    controller = build_controller

    describe "#render_markdown with string" do
      it "renders basic markdown to HTML" do
        result = controller.render_markdown("# Hello")
        result.should contain("<h1>Hello</h1>")
      end

      it "renders paragraph text" do
        result = controller.render_markdown("Hello world")
        result.should eq("<p>Hello world</p>\n")
      end

      it "renders bold text" do
        result = controller.render_markdown("**bold**")
        result.should contain("<strong>bold</strong>")
      end

      it "renders italic text" do
        result = controller.render_markdown("*italic*")
        result.should contain("<em>italic</em>")
      end

      it "renders links" do
        result = controller.render_markdown("[link](http://example.com)")
        result.should contain(%(<a href="http://example.com">link</a>))
      end

      it "renders code blocks" do
        result = controller.render_markdown("```\ncode\n```")
        result.should contain("<pre>")
        result.should contain("<code>")
      end

      it "renders empty string for empty input" do
        result = controller.render_markdown("")
        result.should eq("")
      end

      it "accepts custom options" do
        options = Amber::Markdown::Options.new(toc: true)
        result = controller.render_markdown("# Title", options)
        result.should contain(%(class="anchor"))
      end
    end

    describe "#render_markdown with file" do
      it "renders markdown from a file" do
        # Create a temporary file for testing
        temp_path = File.tempname("test", ".md")
        File.write(temp_path, "# File Heading\n\nFile content.")
        begin
          result = controller.render_markdown(file: temp_path)
          result.should contain("<h1>File Heading</h1>")
          result.should contain("<p>File content.</p>")
        ensure
          File.delete(temp_path) if File.exists?(temp_path)
        end
      end

      it "accepts custom options for file rendering" do
        temp_path = File.tempname("test", ".md")
        File.write(temp_path, "# Title")
        begin
          options = Amber::Markdown::Options.new(toc: true)
          result = controller.render_markdown(file: temp_path, options: options)
          result.should contain(%(class="anchor"))
        ensure
          File.delete(temp_path) if File.exists?(temp_path)
        end
      end
    end
  end
end
