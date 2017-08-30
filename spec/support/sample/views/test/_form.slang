form action="/posts" method="post"
  == csrf_tag
  div.form-group
    input.form-control type="text" name="title" placeholder="Title" value="hey you"
  div.form-group
    textarea.form-control rows="10" name="content" placeholder="Content" = "out there in the cold" 
  button.btn.btn-primary.btn-xs type="submit" Submit
  a.btn.btn-default.btn-xs href="/posts" back
