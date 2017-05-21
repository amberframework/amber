require "../src/controllers/*"

include Crack::Handler
include Kemalyst::Handler

get "/", home, index

# the `resources` macro will create these 7 routes for you:
# get "/demos", demo, index
# get "/demos/new", demo, new
# post "/demos", demo, create
# get "/demos/:id", demo, show
# get "/demos/:id/edit", demo, edit
# patch "/demos/:id", demo, patch
# delete "/demos/:id", demo, delete

# resources Demo

# the `resource` macro will create the following routes for you
# get "/demo/new", demo, new
# post "/demo", demo, create
# get "/demo", demo, show
# get "/demo/edit", demo, edit
# patch "/demo", demo, update
# delete "/demo", demo, delete

# resource Demo
