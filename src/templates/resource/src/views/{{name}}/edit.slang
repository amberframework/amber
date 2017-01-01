h1 Edit Demo

== render "demo/_errors.slang"

form action="/demos/#{ demo.id }" method="post"
  == csrf_tag(context)
  input type="hidden" name="_method" value="put"
  div.form-group
    input.form-control type="text" name="name" placeholder="Name" value="#{ demo.name }"
  div.form-group
    textarea.form-control rows="4" cols="50" name="description" = demo.description
  button.btn.btn-primary.btn-xs type="submit" Submit
  a.btn.btn-default.btn-xs href="/demos" back
