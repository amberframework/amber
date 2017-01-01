doctype html
html
  head
    title Demo using Kemalyst
    meta charset="utf-8"
    meta http-equiv="X-UA-Compatible" content="IE=edge"
    meta name="viewport" content="width=device-width, initial-scale=1"
    meta name="description" content="Demo using Kemalyst"

    link rel="stylesheet" href="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/css/bootstrap.min.css"
    link rel="stylesheet" href="/stylesheets/main.css"

  body
    div.blog-masthead
      div.container
        nav.blog-nav
          a.blog-nav-item.active href="/" Home
          a.blog-nav-item href="/demos/new" New

    div.container
      div.blog-header
        h1.blog-title Demo Site
        p.lead.blog-description Demo using Kemalyst.

      div.row
      - context.flash.each do |key, value|
        div.alert.alert-#{ key }
          p = value
      
      div.row
        div.col-sm-8.blog-main
          == content 

        div.col-sm-3.col-sm-offset-1.blog-sidebar
          div.sidebar-module.sidebar-module-inset
            h4 About
            p This is an example site using Crystal, Kemalyst and the Bootstrap Blog template.

    footer.blog-footer
      p Blog template built for 
        a href="http://getbootstrap.com" Bootstrap
        by 
        a href="https://twitter.com/mdo" @mdo.
    
    script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.3/jquery.min.js"
    script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.3.5/js/bootstrap.min.js"
    script src="/javascripts/main.js"
