require "../src/controllers/*"

include Kemalyst::Handler

# This is an example of how to configure the Basic Authentication handler for
# a path.  In this example, Basic Authentication is configured for the whole
# site.  You could also have added this to the application.cr instead.
# all    "/*",                Kemalyst::Handler::BasicAuth.instance("admin", "password")

post "/*", CSRF
put  "/*", CSRF
patch  "/*", CSRF

# This is how to setup the root path:
get "/", HomeController::Index

# the `resources` macro will create these 7 routes for you:
# get "/demos", DemoController::Index
# get "/demos/new", DemoController::New
# post "/demos", DemoController::Create
# get "/demos/:id", DemoController::Show
# get "/demos/:id/edit", DemoController::Edit
# put "/demos/:id", DemoController::Update
# patch "/demos/:id", DemoController::Update
# delete "/demos/:id", DemoController::Delete

# resources Demo

# the `resource` macro will create the following routes for you
# get "/demo/new", DemoController::New
# post "/demo", DemoController::Create
# get "/demo", DemoController::Show
# get "/demo/edit", DemoController::Edit
# put "/demo", DemoController::Update
# patch "/demo", DemoController::Update
# delete "/demo", DemoController::Delete

# resource Demo

