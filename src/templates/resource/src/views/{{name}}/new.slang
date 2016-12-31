h1 New Demo

== render "demo/_errors.slang"

form action="/demos" method="post"
  == csrf_tag(context)
  div.form-group
    input.form-control type="text" name="name" placeholder="Name" 
  div.form-group
    textarea.form-control rows="4" cols="50" name="description"
  button.btn.btn-primary.btn-xs type="submit" Submit
  a.btn.btn-default.btn-xs href="/demos" back
