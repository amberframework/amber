require "./paired_measurement"
require "./workload"

# Routes the same requests through Amber's router with its own rules and
# with the same rules on Mica (static and runtime) and stdlib Regex, after
# proving every backend accepts exactly the segments Amber's rules accept.
#
#   minecart install --frozen
#   crystal-alpha build --release src/router_vs_mica.cr -o bin/router_vs_mica
#   bin/router_vs_mica results.json <mica commit>
#   /usr/bin/ruby summarize.rb results.json > tables.md
module RouterVsMica
  # Raised when a backend disagrees with Amber's own rule or route result.
  class DisagreementError < Exception
  end

  record CompileCost, backend : String, label : String, microseconds : Float64 do
    include JSON::Serializable
  end

  record Report, mica_commit : String, list_of_backends : Array(String), fuzz_segments_checked : Int32,
    fuzz_paths_checked : Int32, compile_costs : Array(CompileCost), rule_results : Array(PairedResult),
    router_results : Array(PairedResult) do
    include JSON::Serializable
  end

  FUZZ_SEGMENTS   = 20_000
  FUZZ_ALPHABET   = "0123456789abcdefABCDEFxyzXYZ-_.%~é".chars
  MICRO_PATH_HEAD = "/items/"
  MICRO_PATH_TAIL = "/comments"

  def self.check_rule_agreement(rules : Hash(String, Hash(String, Amber::Router::ParamConstraint)),
                                random : Random) : Int32
    checked = 0
    RULE_SOURCES.each_key do |label|
      samples = SEGMENT_SAMPLES[label]
      list_of_segments = [samples.matching, samples.failing_late, samples.failing_early, "", "-", "0" * 300]
      FUZZ_SEGMENTS.times { list_of_segments << random_segment(label, random) }
      list_of_segments.each do |segment|
        path = "#{MICRO_PATH_HEAD}#{segment}#{MICRO_PATH_TAIL}"
        expected = rules["hand"][label].matches_span?(path, MICRO_PATH_HEAD.bytesize, segment.bytesize)
        LIST_OF_BACKENDS.each do |backend|
          rule = rules[backend][label]
          span_answer = rule.matches_span?(path, MICRO_PATH_HEAD.bytesize, segment.bytesize)
          whole_answer = rule.matches?(segment)
          next if span_answer == expected && whole_answer == expected
          raise DisagreementError.new("#{backend} #{label} on #{segment.inspect}: span #{span_answer}, whole #{whole_answer}, hand #{expected}")
        end
        checked += 1
      end
    end
    checked
  end

  # A segment near the rule's shape: a mutated sample, or random text.
  def self.random_segment(label : String, random : Random) : String
    samples = SEGMENT_SAMPLES[label]
    if random.rand(2) == 0
      chars = samples.matching.chars
      random.rand(1..3).times do
        chars[random.rand(chars.size)] = FUZZ_ALPHABET.sample(random)
      end
      chars.pop if random.rand(4) == 0
      chars.join
    else
      String.build { |io| random.rand(0..40).times { io << FUZZ_ALPHABET.sample(random) } }
    end
  end

  def self.check_route_agreement(rules : Hash(String, Hash(String, Amber::Router::ParamConstraint)),
                                 random : Random) : Int32
    checked = 0
    {RouteTable.small, RouteTable.large}.each do |list_of_routes|
      route_sets = LIST_OF_BACKENDS.to_h { |backend| {backend, RouteTable.build(list_of_routes, rules[backend])} }
      list_of_requests = RouteTable.requests(list_of_routes)
      list_of_paths = list_of_requests.map { |request| {request.verb, request.path} }
      list_of_requests.each do |request|
        2_000.times do
          mutated = request.path.split('/').map do |segment|
            random.rand(3) == 0 && !segment.empty? ? random_segment(RULE_SOURCES.keys.sample(random), random) : segment
          end.join('/')
          list_of_paths << {request.verb, mutated}
        end
      end
      list_of_paths.each do |verb, path|
        expected = route_sets["hand"].find_span(verb, path)
        LIST_OF_BACKENDS.each do |backend|
          result = route_sets[backend].find_span(verb, path)
          same = result.found? == expected.found? &&
                 (!expected.found? || (result.payload? == expected.payload? && result.params == expected.params))
          raise DisagreementError.new("#{backend} routes #{verb} #{path} differently") unless same
        end
        checked += 1
      end
    end
    checked
  end

  # One-time cost of building each runtime rule (the static rules are built
  # with the program).
  def self.compile_costs : Array(CompileCost)
    list_of_costs = [] of CompileCost
    RULE_SOURCES.each do |label, source|
      {"mica_runtime_span", "stdlib_span"}.each do |backend|
        list_of_samples = Array(Float64).new(101) do
          started = Time.instant
          if backend == "mica_runtime_span"
            RuleBackend::MicaRuntimeSpan.new(label, source)
          else
            RuleBackend::StdlibSpan.new(label, source)
          end
          (Time.instant - started).total_microseconds
        end
        list_of_costs << CompileCost.new(backend, label, list_of_samples.sort[50])
      end
    end
    list_of_costs
  end

  def self.rule_results(rules : Hash(String, Hash(String, Amber::Router::ParamConstraint))) : Array(PairedResult)
    list_of_results = [] of PairedResult
    RULE_SOURCES.each_key do |label|
      samples = SEGMENT_SAMPLES[label]
      {"match" => samples.matching, "fail_late" => samples.failing_late, "fail_early" => samples.failing_early}.each do |case_name, segment|
        path = "#{MICRO_PATH_HEAD}#{segment}#{MICRO_PATH_TAIL}"
        offset = MICRO_PATH_HEAD.bytesize
        hand = rules["hand"][label]
        repetitions = PairedMeasurement.repetitions_for { hand.matches_span?(path, offset, segment.bytesize) ? 1 : 0 }
        baseline = RuleWorkload.new(hand, path, offset, segment.bytesize, repetitions)
        LIST_OF_BACKENDS.each do |backend|
          next if backend == "hand"
          candidate = RuleWorkload.new(rules[backend][label], path, offset, segment.bytesize, repetitions)
          result = PairedMeasurement.compare("#{label}/#{case_name}", backend, baseline, candidate, repetitions)
          list_of_results << result
          print_result(result)
        end
      end
    end
    list_of_results
  end

  def self.router_results(rules : Hash(String, Hash(String, Amber::Router::ParamConstraint))) : Array(PairedResult)
    list_of_results = [] of PairedResult
    {"20" => RouteTable.small, "200" => RouteTable.large}.each do |size, list_of_routes|
      route_sets = LIST_OF_BACKENDS.to_h { |backend| {backend, RouteTable.build(list_of_routes, rules[backend])} }
      list_of_requests = RouteTable.requests(list_of_routes)
      mixes = {"all" => list_of_requests}
      %w[fixed rule_hit rule_miss unknown].each do |kind|
        mixes[kind] = list_of_requests.select { |request| request.kind == kind }
      end
      mixes.each do |mix_name, mix|
        next if mix.empty?
        hand_set = route_sets["hand"]
        repetitions = PairedMeasurement.repetitions_for { RouterWorkload.new(hand_set, mix, 1).run }
        calls = repetitions * mix.size
        baseline = RouterWorkload.new(hand_set, mix, repetitions)
        LIST_OF_BACKENDS.each do |backend|
          next if backend == "hand"
          candidate = RouterWorkload.new(route_sets[backend], mix, repetitions)
          result = PairedMeasurement.compare("routes#{size}/#{mix_name}(#{mix.size} paths)", backend, baseline, candidate, calls)
          list_of_results << result
          print_result(result)
        end
      end
    end
    list_of_results
  end

  def self.print_result(result : PairedResult) : Nil
    STDOUT.printf("%-34s %-20s hand %9.2f ns  cand %9.2f ns  ratio %.3f [%.3f, %.3f]  bytes %.1f/%.1f  pairs %d\n",
      result.label, result.candidate, result.baseline_ns.center, result.candidate_ns.center,
      result.ratio.center, result.ratio.low, result.ratio.high,
      result.baseline_bytes_per_call, result.candidate_bytes_per_call, result.pairs)
  end

  def self.run(output_path : String, mica_commit : String) : Nil
    rules = rules_by_backend
    random = Random.new(PairedMeasurement::RANDOM_SEED)
    fuzz_segments = check_rule_agreement(rules, random)
    fuzz_paths = check_route_agreement(rules, random)
    STDOUT.puts "agreement: #{fuzz_segments} segments x #{LIST_OF_BACKENDS.size} backends, #{fuzz_paths} paths: all agree with Amber's rules"
    costs = compile_costs
    costs.each { |cost| STDOUT.printf("compile %-18s %-9s %8.2f us\n", cost.backend, cost.label, cost.microseconds) }
    rule_list = rule_results(rules)
    router_list = router_results(rules)
    report = Report.new(mica_commit, LIST_OF_BACKENDS, fuzz_segments, fuzz_paths, costs, rule_list, router_list)
    File.write(output_path, report.to_pretty_json)
    STDOUT.puts "checksum #{PairedMeasurement.checksum}"
  end
end

RouterVsMica.run(ARGV[0]? || "router_vs_mica.json", ARGV[1]? || "unknown")
