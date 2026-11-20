require "./rule_backend"

module RouterVsMica
  # Every rule Amber ships (`ParamConstraints::PRESETS`, a length-bounded
  # `CharacterRun`, and `OneOf`), keyed by label, with the regex body that
  # accepts exactly the same segments. `Custom` runs a block of the app's
  # own code, so it has no regex counterpart and is left out.
  RULE_SOURCES = {
    "numeric"  => "[0-9]+",
    "alpha"    => "[a-zA-Z]+",
    "alnum"    => "[a-zA-Z0-9]+",
    "hex"      => "[0-9a-fA-F]+",
    "slug"     => "[a-z0-9]+(?:-[a-z0-9]+)*",
    "uuid"     => "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}",
    "numeric4" => "[0-9]{4}",
    "one_of"   => "published|archived|draft",
  }

  # Segments for each rule: one it accepts, one that fails on its last byte
  # and one that fails on its first byte.
  record SegmentSamples, matching : String, failing_late : String, failing_early : String

  SEGMENT_SAMPLES = {
    "numeric" => SegmentSamples.new("48213907", "4821390x", "x8213907"),
    "alpha"   => SegmentSamples.new("Overview", "Overvie1", "1verview"),
    "alnum"   => SegmentSamples.new("a1B2c3D4", "a1B2c3D-", "-1B2c3D4"),
    "hex"     => SegmentSamples.new("c0ffee42", "c0ffee4g", "g0ffee42"),
    "slug"    => SegmentSamples.new("hello-amber-world", "hello-amber-world-", "-hello-amber-world"),
    "uuid"    => SegmentSamples.new("550e8400-e29b-41d4-a716-446655440000",
      "550e8400-e29b-41d4-a716-44665544000g", "g50e8400-e29b-41d4-a716-446655440000"),
    "numeric4" => SegmentSamples.new("2026", "202x", "x026"),
    "one_of"   => SegmentSamples.new("published", "publishex", "xublished"),
  }

  # The backends a benchmark compares, in report order. `hand` is Amber's
  # router as released.
  LIST_OF_BACKENDS = %w[hand hand_control mica_static_span mica_runtime_span stdlib_span mica_static_slice mica_runtime_slice stdlib_slice mica_static_span_unchecked]

  # Returns Amber's own rule for *label*.
  def self.hand_rule(label : String) : Amber::Router::ParamConstraint
    case label
    when "numeric"  then Amber::Router::ParamConstraints::NUMERIC
    when "alpha"    then Amber::Router::ParamConstraints::ALPHA
    when "alnum"    then Amber::Router::ParamConstraints::ALNUM
    when "hex"      then Amber::Router::ParamConstraints::HEX
    when "slug"     then Amber::Router::ParamConstraints::SLUG
    when "uuid"     then Amber::Router::ParamConstraints::UUID
    when "numeric4" then Amber::Router::ParamConstraints::NUMERIC.with_length(4)
    when "one_of"   then Amber::Router::ParamConstraints::OneOf.new("draft", "published", "archived")
    else                 raise ArgumentError.new("unknown rule #{label}")
    end
  end

  # Returns, for each backend, the rule for each label.
  def self.rules_by_backend : Hash(String, Hash(String, Amber::Router::ParamConstraint))
    rules = Hash(String, Hash(String, Amber::Router::ParamConstraint)).new
    LIST_OF_BACKENDS.each { |backend| rules[backend] = Hash(String, Amber::Router::ParamConstraint).new }
    RULE_SOURCES.each do |label, source|
      rules["hand"][label] = hand_rule(label)
      # A second, separately built copy of Amber's rules: the A/A control that
      # shows the measurement's own floor.
      rules["hand_control"][label] = hand_rule(label)
      rules["mica_runtime_span"][label] = RuleBackend::MicaRuntimeSpan.new(label, source)
      rules["mica_runtime_slice"][label] = RuleBackend::MicaRuntimeSlice.new(label, "\\A(?:#{source})\\z")
      rules["stdlib_span"][label] = RuleBackend::StdlibSpan.new(label, source)
      rules["stdlib_slice"][label] = RuleBackend::StdlibSlice.new(label, source)
    end
    # Static patterns are compiled while this program builds, so each
    # needs its pattern as a literal here.
    {% for label, source in RULE_SOURCES %}
      rules["mica_static_span"][{{label}}] = RuleBackend::MicaStaticSpan.new({{label}}, Mica::Regex.static({{source}}))
      rules["mica_static_span_unchecked"][{{label}}] = RuleBackend::MicaStaticSpanUnchecked.new({{label}}, Mica::Regex.static({{source}}))
      rules["mica_static_slice"][{{label}}] = RuleBackend::MicaStaticSlice.new({{label}},
        Mica::Regex.static({{"\\A(?:" + source + ")\\z"}}))
    {% end %}
    rules
  end
end
