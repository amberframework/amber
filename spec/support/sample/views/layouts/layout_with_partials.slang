html
  body
    h1
      == render(partial: "spec/support/sample/views/test/_test.slang")
    h2
      == render(partial: "spec/support/sample/views/test/_test2.slang")
    == content
