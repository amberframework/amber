require "benchmark"
require "json"
require "./routers/kemal_radix"

# Cross-framework router benchmark runner.
#
# Runs fresh benchmarks for the radix shard (used by Kemal).
# Amber V1 and V2 data is loaded from existing benchmark results
# to avoid namespace conflicts between the old and new router
# implementations (both define Amber::Router::RouteSet but with
# incompatible struct/class definitions for internal types).
#
# Routes follow a consistent pattern using 30 resources and 10 actions,
# matching the same distribution used in the Amber benchmarks.

RESOURCES = (1..30).map { |i| "resource_#{i}" }
ACTIONS   = (1..10).map { |i| "action_#{i}" }
TIERS     = [50, 100, 500, 1000, 5000, 10000]

# Generates route definitions as an array of {path, payload} tuples.
# Distribution matches the Amber benchmarks:
#   - Fixed:    60% - /resource_N/action_M
#   - Variable: 35% - /resource_N/:id/action_M
#   - Glob:      5% - /resource_N/files/*filepath
def generate_routes(count : Int32) : Array({String, Symbol})
  routes = [] of {String, Symbol}

  # Fixed routes: 60% of total
  num_fixed = (count * 0.6).to_i
  num_fixed.times do |i|
    resource = RESOURCES[i % RESOURCES.size]
    action = ACTIONS[(i // RESOURCES.size) % ACTIONS.size]
    group = i // (RESOURCES.size * ACTIONS.size)
    if group == 0
      routes << {"/#{resource}/#{action}", :"fixed_#{i}"}
    else
      routes << {"/api/v#{group}/#{resource}/#{action}", :"fixed_#{i}"}
    end
  end

  # Variable routes: 35% of total
  num_variable = (count * 0.35).to_i
  num_variable.times do |i|
    resource = RESOURCES[i % RESOURCES.size]
    action = ACTIONS[(i // RESOURCES.size) % ACTIONS.size]
    group = i // (RESOURCES.size * ACTIONS.size)
    if group == 0
      routes << {"/#{resource}/:id/#{action}", :"variable_#{i}"}
    else
      routes << {"/api/v#{group}/#{resource}/:id/#{action}", :"variable_#{i}"}
    end
  end

  # Glob routes: 5% of total
  num_glob = (count * 0.05).to_i
  num_glob.times do |i|
    resource = RESOURCES[i % RESOURCES.size]
    group = i // RESOURCES.size
    if group == 0
      routes << {"/#{resource}/files/*filepath", :"glob_#{i}"}
    else
      routes << {"/#{resource}/assets/v#{group}/*filepath", :"glob_#{i}"}
    end
  end

  routes
end

# Sample lookup paths for each lookup type.
def fixed_lookup_path(tier : Int32) : String
  i = [tier // 3, 1].max
  resource = RESOURCES[i % RESOURCES.size]
  action = ACTIONS[(i // RESOURCES.size) % ACTIONS.size]
  group = i // (RESOURCES.size * ACTIONS.size)
  if group == 0
    "/#{resource}/#{action}"
  else
    "/api/v#{group}/#{resource}/#{action}"
  end
end

def variable_lookup_path(tier : Int32) : String
  i = [tier // 5, 1].max
  resource = RESOURCES[i % RESOURCES.size]
  action = ACTIONS[(i // RESOURCES.size) % ACTIONS.size]
  group = i // (RESOURCES.size * ACTIONS.size)
  if group == 0
    "/#{resource}/42/#{action}"
  else
    "/api/v#{group}/#{resource}/42/#{action}"
  end
end

def glob_lookup_path(tier : Int32) : String
  "/resource_1/files/path/to/deep/nested/file.txt"
end

def notfound_lookup_path : String
  "/definitely/not/a/real/route/anywhere"
end

alias BenchEntry = Hash(String, String | Float64)

# --- Load existing Amber benchmark data ---

def load_amber_v2_data : Array(BenchEntry)
  entries = [] of BenchEntry
  path = File.join(__DIR__, "..", "..", "results", "final_expanded.json")

  unless File.exists?(path)
    STDERR.puts "WARNING: Amber V2 data not found at #{path}"
    return entries
  end

  raw = Array(Hash(String, String)).from_json(File.read(path))
  raw.each do |row|
    tier = row["tier"].to_f64
    next unless TIERS.includes?(tier.to_i)

    # Extract each lookup type from the row
    [
      {"fixed", row["ips_fixed"], row["memory_fixed_bytes"]},
      {"variable", row["ips_variable"], row["memory_variable_bytes"]},
      {"glob", row["ips_glob"], row["memory_glob_bytes"]},
      {"notfound", row["ips_notfound"], row["memory_notfound_bytes"]},
    ].each do |(lookup_type, ips_str, mem_str)|
      entries << {
        "router"       => "Amber V2",
        "tier"         => tier,
        "lookup_type"  => lookup_type,
        "ips"          => ips_str.to_f64,
        "memory_bytes" => mem_str.to_f64,
      } of String => String | Float64
    end
  end

  entries
end

def load_amber_v1_data : Array(BenchEntry)
  entries = [] of BenchEntry
  path = File.join(__DIR__, "..", "..", "results", "baseline_expanded.json")

  unless File.exists?(path)
    STDERR.puts "WARNING: Amber V1 data not found at #{path}"
    return entries
  end

  raw = Array(Hash(String, String)).from_json(File.read(path))
  raw.each do |row|
    tier = row["tier"].to_f64
    next unless TIERS.includes?(tier.to_i)

    [
      {"fixed", row["ips_fixed"], row["memory_fixed_bytes"]},
      {"variable", row["ips_variable"], row["memory_variable_bytes"]},
      {"glob", row["ips_glob"], row["memory_glob_bytes"]},
      {"notfound", row["ips_notfound"], row["memory_notfound_bytes"]},
    ].each do |(lookup_type, ips_str, mem_str)|
      entries << {
        "router"       => "Amber V1 (amber_router)",
        "tier"         => tier,
        "lookup_type"  => lookup_type,
        "ips"          => ips_str.to_f64,
        "memory_bytes" => mem_str.to_f64,
      } of String => String | Float64
    end
  end

  entries
end

# --- Run fresh radix benchmarks ---

def run_radix_benchmarks : Array(BenchEntry)
  entries = [] of BenchEntry

  TIERS.each do |tier|
    routes = generate_routes(tier)
    router = KemalRadixRouter.new

    # Register all routes
    reg_time = Benchmark.realtime do
      routes.each do |path, payload|
        router.add_route(path, payload)
      end
    end

    puts "\n#{"=" * 60}"
    puts "  radix (Kemal) - TIER: #{tier} routes (#{routes.size} registered in #{reg_time.total_milliseconds.round(3)}ms)"
    puts "=" * 60

    # Lookup paths
    fp = fixed_lookup_path(tier)
    vp = variable_lookup_path(tier)
    gp = glob_lookup_path(tier)
    nfp = notfound_lookup_path

    # Verify lookups work correctly
    puts "  Verify: fixed=#{router.lookup(fp)} variable=#{router.lookup(vp)} glob=#{router.lookup(gp)} notfound=#{router.lookup(nfp)}"

    # Memory benchmarks
    mem_fixed = Benchmark.memory { router.lookup(fp) }
    mem_variable = Benchmark.memory { router.lookup(vp) }
    mem_glob = Benchmark.memory { router.lookup(gp) }
    mem_notfound = Benchmark.memory { router.lookup(nfp) }

    puts "  Memory: fixed=#{mem_fixed}B variable=#{mem_variable}B glob=#{mem_glob}B notfound=#{mem_notfound}B"

    # IPS benchmarks for each lookup type
    [
      {:fixed, fp, mem_fixed},
      {:variable, vp, mem_variable},
      {:glob, gp, mem_glob},
      {:notfound, nfp, mem_notfound},
    ].each do |(lookup_type, path, memory)|
      job = Benchmark.ips(warmup: 2.seconds, calculation: 5.seconds) do |x|
        x.report("radix #{lookup_type} #{tier}r") { router.lookup(path) }
      end

      ips_value = job.items.first.mean

      entries << {
        "router"       => "radix (Kemal)",
        "tier"         => tier.to_f64,
        "lookup_type"  => lookup_type.to_s,
        "ips"          => ips_value.round(2),
        "memory_bytes" => memory.to_f64,
      } of String => String | Float64

      puts "  #{lookup_type}: #{ips_value.round(0)} IPS, #{memory} bytes/lookup"
    end
  end

  entries
end

# --- Main ---

puts "Cross-Framework Router Benchmark"
puts "Crystal #{Crystal::VERSION}"
puts "================================\n"

# Load existing data
puts "Loading existing Amber V2 data..."
amber_v2_data = load_amber_v2_data
puts "  Loaded #{amber_v2_data.size} entries"

puts "Loading existing Amber V1 data..."
amber_v1_data = load_amber_v1_data
puts "  Loaded #{amber_v1_data.size} entries"

# Run fresh radix benchmarks
puts "\nRunning fresh radix (Kemal) benchmarks..."
radix_data = run_radix_benchmarks

# Merge all results
all_results = amber_v2_data + amber_v1_data + radix_data

# Write combined results
output_path = File.join(__DIR__, "..", "results", "comparison.json")
Dir.mkdir_p(File.dirname(output_path))
File.write(output_path, all_results.to_pretty_json)

puts "\n\n#{"=" * 60}"
puts "Results written to #{output_path}"
puts "Total entries: #{all_results.size}"
puts "  Amber V2: #{amber_v2_data.size} entries"
puts "  Amber V1: #{amber_v1_data.size} entries"
puts "  radix:    #{radix_data.size} entries"
