- demos.each do |demo|
  div.blog-post
    h2.blog-post-title = demo.name
    p.blog-description == Markdown.to_html(demo.description || "")
    p.blog-post-meta = demo.last_updated

    p
      a.btn.btn-primary.btn-xs href="/demos/#{ demo.id }" read
      a.btn.btn-success.btn-xs href="/demos/#{ demo.id }/edit" edit
      a.btn.btn-danger.btn-xs href="/demos/#{ demo.id }?_method=delete" onclick="return confirm('Are you sure?');" delete
