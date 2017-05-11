require "../src/controllers/*"

include Kemalyst::Handler

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

