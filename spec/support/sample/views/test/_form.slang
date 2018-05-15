form action="/posts" method="post"
  == csrf_tag
  .form-group
    input.form-control type="text" name="title" placeholder="Title" value="hey you"
  .form-group
    textarea.form-control rows="10" name="content" placeholder="Content" = "out there in the cold"
  button.btn.btn-primary.btn-sm type="submit" Submit
  a.btn.btn-light.btn-sm href="/posts" back
