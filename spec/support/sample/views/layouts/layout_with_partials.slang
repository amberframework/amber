html
  body
    h1
      == render(path: "spec/support/sample/views", partial: "test/_test.slang")
    h2
      == render(path: "spec/support/sample/views", partial: "test/_test2.slang")
    == content
