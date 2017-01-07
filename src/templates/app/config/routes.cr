require "../src/controllers/*"

include Kemalyst::Handler

# This is an example of how to configure the Basic Authentication handler for
# a path.  In this example, Basic Authentication is configured for the whole
# site.  You could also have added this to the application.cr instead.
# all    "/*",                Kemalyst::Handler::BasicAuth.instance("admin", "password")

post "/*", CSRF
put  "/*", CSRF

# This is how to setup the root path:
get "/", StaticController::Index

# This is an example of a resource using a traditional site:
# get "/demos", DemoController::Index
# get "/demos/new", DemoController::New
# post "/demos", DemoController::Create
# get "/demos/:id", DemoController::Show
# get "/demos/:id/edit", DemoController::Edit
# put "/demos/:id", DemoController::Update
# delete "/demos/:id", DemoController::Delete

# the `resource` macro will create the 7 routes for you:
# resource Demo
