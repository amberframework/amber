require "uri"

module Amber::Markdown
  class HTMLRenderer < Renderer
    @disable_tag = 0
    @last_output = "\n"
    @footnote_references = [] of String
    @footnote_definitions = {} of String => String
    @toc_entries = [] of {level: Int32, text: String, anchor: String}
    @collecting_heading_text = false
    @heading_text_builder = String::Builder.new

    HEADINGS = %w(h1 h2 h3 h4 h5 h6)

    def heading(node : Node, entering : Bool)
      tag_name = HEADINGS[node.data["level"].as(Int32) - 1]
      if entering
        newline
        tag(tag_name, attrs(node))
        toc(node) if @options.toc
        @collecting_heading_text = true
        @heading_text_builder = String::Builder.new
      else
        if @collecting_heading_text
          @collecting_heading_text = false
          heading_text = @heading_text_builder.to_s
          level = node.data["level"].as(Int32)
          anchor = heading_anchor(heading_text)
          @toc_entries << {level: level, text: heading_text, anchor: anchor}
        end
        tag(tag_name, end_tag: true)
        newline
      end
    end

    def code(node : Node, entering : Bool)
      tag("code") do
        code_body(node)
      end
    end

    def code_body(node : Node)
      output(node.text)
    end

    def code_block(node : Node, entering : Bool)
      languages = node.fence_language ? node.fence_language.split : nil
      lang = code_block_language(languages)

      if highlighter = @options.code_highlighter
        newline
        highlighted = highlighter.call(node.text, lang || "")
        literal(highlighted)
        newline
      else
        code_tag_attrs = attrs(node)
        pre_tag_attrs = if @options.prettyprint?
                          {"class" => "prettyprint"}
                        else
                          nil
                        end

        if lang
          code_tag_attrs ||= {} of String => String
          code_tag_attrs["class"] = "language-#{escape(lang)}"
        end

        newline
        tag("pre", pre_tag_attrs) do
          tag("code", code_tag_attrs) do
            code_block_body(node, lang)
          end
        end
        newline
      end
    end

    def code_block_language(languages)
      languages.try(&.first?).try(&.strip.presence)
    end

    def code_block_body(node : Node, lang : String?)
      output(node.text)
    end

    def thematic_break(node : Node, entering : Bool)
      newline
      tag("hr", attrs(node), self_closing: true)
      newline
    end

    def block_quote(node : Node, entering : Bool)
      newline
      if entering
        tag("blockquote", attrs(node))
      else
        tag("blockquote", end_tag: true)
      end
      newline
    end

    def list(node : Node, entering : Bool)
      tag_name = node.data["type"] == "bullet" ? "ul" : "ol"

      newline
      if entering
        attrs = attrs(node)

        if (start = node.data["start"].as(Int32)) && start != 1
          attrs ||= {} of String => String
          attrs["start"] = start.to_s
        end

        tag(tag_name, attrs)
      else
        tag(tag_name, end_tag: true)
      end
      newline
    end

    def item(node : Node, entering : Bool)
      if entering
        if node.data.has_key?("task")
          is_checked = node.data["task"].as(Bool)
          checked_attr = is_checked ? " checked=\"\"" : ""
          tag("li", attrs(node))
          literal("<input type=\"checkbox\" disabled=\"\"#{checked_attr} /> ")
        else
          tag("li", attrs(node))
        end
      else
        tag("li", end_tag: true)
        newline
      end
    end

    def link(node : Node, entering : Bool)
      if entering
        attrs = attrs(node)
        destination = node.data["destination"].as(String)

        unless @options.safe? && potentially_unsafe(destination)
          attrs ||= {} of String => String
          destination = resolve_uri(destination, node)
          attrs["href"] = escape(destination)
        end

        if (title = node.data["title"].as(String)) && !title.empty?
          attrs ||= {} of String => String
          attrs["title"] = escape(title)
        end

        tag("a", attrs)
      else
        tag("a", end_tag: true)
      end
    end

    private def resolve_uri(destination, node)
      base_url = @options.base_url
      return destination unless base_url

      uri = URI.parse(destination)
      return destination if uri.absolute?

      base_url.resolve(uri).to_s
    end

    def image(node : Node, entering : Bool)
      if entering
        if @disable_tag == 0
          destination = node.data["destination"].as(String)
          if @options.safe? && potentially_unsafe(destination)
            literal(%(<img src="" alt=""))
          else
            destination = resolve_uri(destination, node)
            literal(%(<img src="#{escape(destination)}" alt="))
          end
        end
        @disable_tag += 1
      else
        @disable_tag -= 1
        if @disable_tag == 0
          if (title = node.data["title"].as(String)) && !title.empty?
            literal(%(" title="#{escape(title)}))
          end
          literal(%(" />))
        end
      end
    end

    def html_block(node : Node, entering : Bool)
      newline
      content = @options.safe? ? "<!-- raw HTML omitted -->" : node.text
      literal(content)
      newline
    end

    def html_inline(node : Node, entering : Bool)
      content = @options.safe? ? "<!-- raw HTML omitted -->" : node.text
      literal(content)
    end

    def paragraph(node : Node, entering : Bool)
      if (grand_parent = node.parent?.try &.parent?) && grand_parent.type.list?
        return if grand_parent.data["tight"]
      end

      if entering
        newline
        tag("p", attrs(node))
      else
        tag("p", end_tag: true)
        newline
      end
    end

    def emphasis(node : Node, entering : Bool)
      tag("em", end_tag: !entering)
    end

    def soft_break(node : Node, entering : Bool)
      literal("\n")
    end

    def line_break(node : Node, entering : Bool)
      tag("br", self_closing: true)
      newline
    end

    def strong(node : Node, entering : Bool)
      tag("strong", end_tag: !entering)
    end

    def text(node : Node, entering : Bool)
      output(node.text)
      if @collecting_heading_text
        @heading_text_builder << node.text
      end
    end

    def table(node : Node, entering : Bool)
      newline
      if entering
        tag("table", attrs(node))
      else
        tag("table", end_tag: true)
      end
      newline
    end

    def table_head(node : Node, entering : Bool)
      newline
      if entering
        tag("thead")
      else
        tag("thead", end_tag: true)
      end
      newline
    end

    def table_body(node : Node, entering : Bool)
      newline
      if entering
        tag("tbody")
      else
        tag("tbody", end_tag: true)
      end
      newline
    end

    def table_row(node : Node, entering : Bool)
      newline
      if entering
        tag("tr")
      else
        tag("tr", end_tag: true)
      end
      newline
    end

    def table_cell(node : Node, entering : Bool)
      tag_name = node.data["header"]?.try(&.as(Bool)) ? "th" : "td"
      if entering
        cell_attrs = attrs(node)
        align = node.data["align"]?.try(&.as(String))
        if align && !align.empty?
          cell_attrs ||= {} of String => String
          cell_attrs["style"] = "text-align: #{align}"
        end
        tag(tag_name, cell_attrs)
      else
        tag(tag_name, end_tag: true)
      end
    end

    def strikethrough(node : Node, entering : Bool)
      tag("del", end_tag: !entering)
    end

    def footnote_reference(node : Node, entering : Bool)
      return unless entering

      label = node.data["label"].as(String)
      # Track the reference order for numbering
      index = @footnote_references.index(label)
      unless index
        @footnote_references << label
        index = @footnote_references.size - 1
      end
      number = index + 1

      literal(%(<sup class="footnote-ref"><a href="#fn-#{escape(label)}" id="fnref-#{escape(label)}">#{number}</a></sup>))
    end

    def footnote_definition(node : Node, entering : Bool)
      return unless entering

      label = node.data["label"].as(String)
      @footnote_definitions[label] = node.text
    end

    # Returns the collected TOC entries for generating a table of contents.
    def toc_entries
      @toc_entries
    end

    # Generates the TOC HTML string from collected heading entries.
    def generate_toc_html : String
      return "" if @toc_entries.empty?

      io = String::Builder.new
      io << %(<ul class="toc">\n)
      @toc_entries.each do |entry|
        io << %(<li class="toc-level-#{entry[:level]}"><a href="#anchor-#{entry[:anchor]}">#{escape(entry[:text])}</a></li>\n)
      end
      io << %(</ul>\n)
      io.to_s
    end

    # Render the document and append footnotes section if needed.
    def render(document : Node)
      html = super

      # Append footnotes section if any footnotes were referenced
      unless @footnote_references.empty?
        footnotes_io = String::Builder.new
        footnotes_io << %(\n<section class="footnotes">\n<ol>\n)
        @footnote_references.each_with_index do |label, index|
          number = index + 1
          content = @footnote_definitions[label]? || ""
          footnotes_io << %(<li id="fn-#{escape(label)}">\n<p>#{escape(content)} <a href="#fnref-#{escape(label)}">&#8617;</a></p>\n</li>\n)
        end
        footnotes_io << %(</ol>\n</section>\n)
        html += footnotes_io.to_s
      end

      html
    end

    private def heading_anchor(text : String) : String
      {% if Crystal::VERSION < "1.2.0" %}
        URI.encode(text)
      {% else %}
        URI.encode_path(text)
      {% end %}
    end

    private def tag(name : String, attrs = nil, self_closing = false, end_tag = false)
      return if @disable_tag > 0

      @output_io << "<"
      @output_io << "/" if end_tag
      @output_io << name
      attrs.try &.each do |key, value|
        @output_io << ' ' << key << '=' << '"' << value << '"'
      end

      @output_io << " /" if self_closing
      @output_io << ">"
      @last_output = ">"
    end

    private def tag(name : String, attrs = nil, &)
      tag(name, attrs)
      yield
      tag(name, end_tag: true)
    end

    private def potentially_unsafe(url : String)
      url.match(Rule::UNSAFE_PROTOCOL) && !url.match(Rule::UNSAFE_DATA_PROTOCOL)
    end

    private def toc(node : Node)
      return unless node.type.heading?

      {% if Crystal::VERSION < "1.2.0" %}
        title = URI.encode(node.first_child.text)
        @output_io << %(<a id="anchor-) << title << %(" class="anchor" href="#anchor-) << title << %("></a>)
      {% else %}
        title = URI.encode_path(node.first_child.text)
        @output_io << %(<a id="anchor-) << title << %(" class="anchor" href="#anchor-) << title << %("></a>)
      {% end %}
      @last_output = ">"
    end

    private def attrs(node : Node)
      if @options.source_pos? && (pos = node.source_pos)
        {"data-source-pos" => "#{pos[0][0]}:#{pos[0][1]}-#{pos[1][0]}:#{pos[1][1]}"}
      else
        nil
      end
    end
  end
end
