require "benchmark"
require "../src/amber/router/engine"

# Route parameter rules: lookups through numeric, slug and UUID rules, a rule
# that fails and falls through to an unconstrained sibling, and a route with
# no rule for comparison.
#
#   crystal build --release benchmarks/router_constraints.cr -o bin/router_constraints
#   bin/router_constraints
router = Amber::Router::RouteSet(Symbol).new
router.add "/posts/:id", :post, {"id" => :numeric}
router.add "/articles/:slug", :article, {"slug" => :slug}
router.add "/objects/:uuid", :object, {"uuid" => :uuid}
router.add "/items/:id", :item_by_number, {"id" => :numeric}
router.add "/items/:name", :item_by_name
router.add "/plain/:id", :plain

lookups = {
  "digits hit " => "/posts/12345",
  "digits miss" => "/posts/12a45",
  "slug hit   " => "/articles/hello-amber-world",
  "uuid hit   " => "/objects/550e8400-e29b-41d4-a716-446655440000",
  "fallback   " => "/items/widget",
  "no rule    " => "/plain/12345",
}
lookups.each_value { |path| router.find(path) }

Benchmark.ips(calculation: 3.seconds, warmup: 1.second) do |x|
  lookups.each do |label, path|
    x.report(label) { router.find(path) }
  end
end
