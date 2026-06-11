require "spec"
require "../../../src/amber/markdown"

describe "GFM Tables" do
  describe "basic table with header" do
    it "renders a simple table" do
      markdown = "| Heading 1 | Heading 2 |\n| --- | --- |\n| Cell 1 | Cell 2 |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("<thead>")
      result.should contain("<th>Heading 1</th>")
      result.should contain("<th>Heading 2</th>")
      result.should contain("<tbody>")
      result.should contain("<td>Cell 1</td>")
      result.should contain("<td>Cell 2</td>")
      result.should contain("</table>")
    end

    it "renders a table with multiple body rows" do
      markdown = "| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<th>A</th>")
      result.should contain("<th>B</th>")
      result.should contain("<td>1</td>")
      result.should contain("<td>2</td>")
      result.should contain("<td>3</td>")
      result.should contain("<td>4</td>")
      # Should have two body rows
      result.scan(/<tr>/).size.should eq(3) # 1 header + 2 body
    end

    it "renders a header-only table (no body rows)" do
      markdown = "| A | B |\n| --- | --- |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("<thead>")
      result.should contain("<th>A</th>")
      result.should contain("<th>B</th>")
      result.should_not contain("<tbody>")
      result.should contain("</table>")
    end
  end

  describe "table with alignment" do
    it "renders left alignment" do
      markdown = "| Left |\n| :--- |\n| data |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain(%(<th style="text-align: left">Left</th>))
      result.should contain(%(<td style="text-align: left">data</td>))
    end

    it "renders center alignment" do
      markdown = "| Center |\n| :---: |\n| data |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain(%(<th style="text-align: center">Center</th>))
      result.should contain(%(<td style="text-align: center">data</td>))
    end

    it "renders right alignment" do
      markdown = "| Right |\n| ---: |\n| data |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain(%(<th style="text-align: right">Right</th>))
      result.should contain(%(<td style="text-align: right">data</td>))
    end

    it "renders mixed alignment" do
      markdown = "| Left | Center | Right | Default |\n| :--- | :---: | ---: | --- |\n| a | b | c | d |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain(%(<th style="text-align: left">Left</th>))
      result.should contain(%(<th style="text-align: center">Center</th>))
      result.should contain(%(<th style="text-align: right">Right</th>))
      result.should contain("<th>Default</th>")
      result.should contain(%(<td style="text-align: left">a</td>))
      result.should contain(%(<td style="text-align: center">b</td>))
      result.should contain(%(<td style="text-align: right">c</td>))
      result.should contain("<td>d</td>")
    end
  end

  describe "table with inline formatting in cells" do
    it "renders bold text in cells" do
      markdown = "| Header |\n| --- |\n| **bold** |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<td><strong>bold</strong></td>")
    end

    it "renders italic text in cells" do
      markdown = "| Header |\n| --- |\n| *italic* |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<td><em>italic</em></td>")
    end

    it "renders code in cells" do
      markdown = "| Header |\n| --- |\n| `code` |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<td><code>code</code></td>")
    end

    it "renders links in cells" do
      markdown = "| Header |\n| --- |\n| [link](http://example.com) |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain(%(<td><a href="http://example.com">link</a></td>))
    end
  end

  describe "table with escaped pipes in cells" do
    it "renders escaped pipes as literal pipes" do
      markdown = "| Header |\n| --- |\n| foo \\| bar |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("foo | bar")
    end
  end

  describe "table without closing pipes" do
    it "renders tables without leading/trailing pipes" do
      markdown = "Heading 1 | Heading 2\n--- | ---\nCell 1 | Cell 2"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("<th>Heading 1</th>")
      result.should contain("<th>Heading 2</th>")
      result.should contain("<td>Cell 1</td>")
      result.should contain("<td>Cell 2</td>")
    end
  end

  describe "edge cases" do
    it "renders a single column table" do
      markdown = "| A |\n| --- |\n| 1 |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("<th>A</th>")
      result.should contain("<td>1</td>")
    end

    it "renders empty cells" do
      markdown = "| A | B |\n| --- | --- |\n| | data |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("<td></td>")
      result.should contain("<td>data</td>")
    end

    it "handles mismatched column counts by padding" do
      markdown = "| A | B | C |\n| --- | --- | --- |\n| 1 |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<th>A</th>")
      result.should contain("<th>B</th>")
      result.should contain("<th>C</th>")
      result.should contain("<td>1</td>")
      # Should have empty padding cells
      result.scan(/<td><\/td>/).size.should eq(2)
    end

    it "truncates extra columns in body rows" do
      markdown = "| A | B |\n| --- | --- |\n| 1 | 2 | 3 | 4 |"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<td>1</td>")
      result.should contain("<td>2</td>")
      result.should_not contain("<td>3</td>")
      result.should_not contain("<td>4</td>")
    end

    it "table followed by paragraph" do
      markdown = "| A |\n| --- |\n| 1 |\n\nParagraph after table"
      result = Amber::Markdown.to_html(markdown)
      result.should contain("<table>")
      result.should contain("</table>")
      result.should contain("<p>Paragraph after table</p>")
    end

    it "does not treat non-table separator as table" do
      markdown = "Not a table\n--- not valid"
      result = Amber::Markdown.to_html(markdown)
      result.should_not contain("<table>")
    end
  end
end
