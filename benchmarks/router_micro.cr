require "benchmark"
require "json"
require "../src/amber/router/engine"

# Generate realistic route sets at each tier.
# Distribution: 60% fixed, 25% variable, 10% constrained, 5% glob.
# Designed to produce unique routes up to 10000+ without collisions.
def generate_routes(count : Int32) : Array({String, Symbol})
  routes = [] of {String, Symbol}
  resources = ["users", "posts", "comments", "tags", "categories",
               "products", "orders", "invoices", "settings", "teams",
               "projects", "tasks", "notifications", "messages", "files",
               "accounts", "roles", "permissions", "sessions", "tokens",
               "webhooks", "events", "logs", "audits", "reports",
               "dashboards", "widgets", "charts", "exports", "imports"]

  actions = ["index", "new", "create", "search", "export",
             "list", "show", "stats", "archive", "restore"]

  # 60% fixed -- unique via resource/action/version/group combos
  num_fixed = (count * 0.6).to_i
  base_combos = resources.size * actions.size # 30 * 10 = 300
  num_fixed.times do |i|
    resource = resources[i % resources.size]
    action = actions[(i // resources.size) % actions.size]
    group = i // base_combos
    if group == 0
      routes << {"/#{resource}/#{action}", :"fixed_#{i}"}
    elsif group <= 3
      routes << {"/api/v#{group}/#{resource}/#{action}", :"fixed_#{i}"}
    else
      routes << {"/api/v#{((group - 1) % 3) + 1}/g#{group}/#{resource}/#{action}", :"fixed_#{i}"}
    end
  end

  # 25% variable -- unique via resource + suffix combos
  num_variable = (count * 0.25).to_i
  num_variable.times do |i|
    resource = resources[i % resources.size]
    suffix = i // resources.size
    if suffix == 0
      routes << {"/#{resource}/:id", :"variable_#{i}"}
    else
      routes << {"/#{resource}/:id/detail#{suffix}", :"variable_#{i}"}
    end
  end

  # 10% constrained -- unique via resource + suffix combos
  num_constrained = (count * 0.1).to_i
  num_constrained.times do |i|
    resource = resources[i % resources.size]
    suffix = i // resources.size
    if suffix == 0
      routes << {"/#{resource}/:id/edit", :"constrained_#{i}"}
    else
      routes << {"/#{resource}/:id/edit#{suffix}", :"constrained_#{i}"}
    end
  end

  # 5% glob -- unique via version + index
  num_glob = (count * 0.05).to_i
  num_glob.times do |i|
    routes << {"/assets/v#{(i % 5) + 1}/*path#{i}", :"glob_#{i}"}
  end

  routes
end

# Build a populated RouteSet from generated routes
def build_router(routes : Array({String, Symbol})) : Amber::Router::RouteSet(Symbol)
  router = Amber::Router::RouteSet(Symbol).new
  routes.each do |path, payload|
    router.add(path, payload)
  end
  router
end

tiers = [50, 100, 200, 500, 1000, 2000, 5000, 10000]

results = [] of Hash(String, String)

tiers.each do |tier|
  routes = generate_routes(tier)

  # --- Registration benchmark ---
  reg_time = Benchmark.realtime do
    build_router(routes)
  end

  # --- Build router for lookup tests ---
  router = build_router(routes)

  # Select representative lookup paths
  fixed_path = "/users/index"
  variable_path = "/users/#{rand(10000)}"
  glob_path = "/assets/v1/some/deep/nested/path"
  notfound_path = "/definitely/not/a/real/#{rand(100000)}/route"

  # --- Memory per lookup ---
  mem_fixed = Benchmark.memory { router.find(fixed_path) }
  mem_variable = Benchmark.memory { router.find(variable_path) }
  mem_glob = Benchmark.memory { router.find(glob_path) }
  mem_notfound = Benchmark.memory { router.find(notfound_path) }

  puts "\n=== Tier: #{tier} routes (registered in #{reg_time.total_milliseconds.round(3)}ms) ==="
  puts "  Memory per lookup: fixed=#{mem_fixed}B variable=#{mem_variable}B glob=#{mem_glob}B notfound=#{mem_notfound}B"

  # Capture IPS results from the benchmark job
  job = Benchmark.ips(calculation: 5.seconds, warmup: 2.seconds) do |x|
    x.report("#{tier}r fixed    ") { router.find(fixed_path) }
    x.report("#{tier}r variable ") { router.find(variable_path) }
    x.report("#{tier}r glob     ") { router.find(glob_path) }
    x.report("#{tier}r notfound ") { router.find(notfound_path) }
  end

  # Extract IPS (mean) from job items: fixed, variable, glob, notfound
  items = job.items
  ips_fixed = items[0].mean
  ips_variable = items[1].mean
  ips_glob = items[2].mean
  ips_notfound = items[3].mean

  results << {
    "tier"                  => tier.to_s,
    "registration_ms"       => reg_time.total_milliseconds.round(6).to_s,
    "memory_fixed_bytes"    => mem_fixed.to_s,
    "memory_variable_bytes" => mem_variable.to_s,
    "memory_glob_bytes"     => mem_glob.to_s,
    "memory_notfound_bytes" => mem_notfound.to_s,
    "ips_fixed"             => ips_fixed.round(2).to_s,
    "ips_variable"          => ips_variable.round(2).to_s,
    "ips_glob"              => ips_glob.round(2).to_s,
    "ips_notfound"          => ips_notfound.round(2).to_s,
  }
end

# Output as JSON for tracking
output_path = "benchmarks/results/final_expanded.json"
File.write(output_path, results.to_pretty_json)
puts "\nResults written to #{output_path}"
