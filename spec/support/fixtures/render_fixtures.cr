module RenderFixtures
  def page_template
    partial_only
  end

  def form_with_csrf(csrf_token)
    <<-HTML
    <form action="/posts" method="post">
      <input type="hidden" name="_csrf" value="#{csrf_token}" />
      <div class="form-group">
        <input class="form-control" type="text" name="title" placeholder="Title" value="hey you">
      </div>
      <div class="form-group">
        <textarea class="form-control" rows="10" name="content" placeholder="Content">out there in the cold</textarea>
      </div>
      <button class="btn btn-primary btn-sm" type="submit">Submit</button>
      <a class="btn btn-light btn-sm" href="/posts">back</a>
    </form>
    HTML
  end

  def layout_with_template
    <<-HTML
    <html>
      <body>
        #{partial_only}
      </body>
    </html>
    HTML
  end

  def layout_with_multiple_partials
    <<-HTML
    <html>
      <body>
        <h1>
          #{partial_only}
        </h1>
        <h2>
          <p>second partial</p>
        </h2>
        #{partial_only}
      </body>
    </html>
    HTML
  end

  def partial_only
    <<-HTML
    <h1>Hello World</h1>
    <p>I am glad you came</p>
    HTML
  end
end
