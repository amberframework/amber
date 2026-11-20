require "./rule_catalog"

module RouterVsMica
  # One route as an app would draw it: verb, path, and the rule label for
  # each constrained parameter.
  record RouteDefinition, verb : String, path : String, rule_labels : Hash(String, String)

  # One request the benchmark routes. `kind` groups requests in the report:
  # `fixed` (no parameter), `rule_hit` (a rule accepts the segment),
  # `rule_miss` (a rule rejects it) and `unknown` (no route at all).
  record RouteRequest, verb : String, path : String, kind : String

  # A realistic route table and the requests routed through it.
  module RouteTable
    RESOURCES = %w[posts users comments tags categories products orders invoices settings teams
      projects tasks notifications messages files accounts roles permissions sessions tokens
      webhooks events reports dashboards exports]

    # The rules that rotate across resources in the 200-route table, so
    # every rule appears in it.
    ROTATING_RULES = %w[slug uuid hex alpha alnum numeric4 one_of]

    # Returns the 20-route table: a small app with one resource of each
    # common shape and every built-in rule.
    def self.small : Array(RouteDefinition)
      none = {} of String => String
      [
        RouteDefinition.new("get", "/", none),
        RouteDefinition.new("get", "/posts", none),
        RouteDefinition.new("get", "/posts/new", none),
        RouteDefinition.new("get", "/posts/:id", {"id" => "numeric"}),
        RouteDefinition.new("get", "/posts/:id/edit", {"id" => "numeric"}),
        RouteDefinition.new("post", "/posts", none),
        RouteDefinition.new("put", "/posts/:id", {"id" => "numeric"}),
        RouteDefinition.new("delete", "/posts/:id", {"id" => "numeric"}),
        RouteDefinition.new("get", "/posts/state/:state", {"state" => "one_of"}),
        RouteDefinition.new("get", "/articles/:slug", {"slug" => "slug"}),
        RouteDefinition.new("get", "/users/:id", {"id" => "numeric"}),
        RouteDefinition.new("get", "/users/:handle", none),
        RouteDefinition.new("get", "/objects/:uuid", {"uuid" => "uuid"}),
        RouteDefinition.new("get", "/orders/:order_id/items", {"order_id" => "uuid"}),
        RouteDefinition.new("get", "/commits/:sha", {"sha" => "hex"}),
        RouteDefinition.new("get", "/locales/:lang", {"lang" => "alpha"}),
        RouteDefinition.new("get", "/codes/:code", {"code" => "alnum"}),
        RouteDefinition.new("get", "/archive/:year", {"year" => "numeric4"}),
        RouteDefinition.new("get", "/archive/:year/:month", {"year" => "numeric4", "month" => "numeric"}),
        RouteDefinition.new("get", "/assets/*path", none),
      ]
    end

    # Returns the 200-route table: 25 resources with eight routes each.
    def self.large : Array(RouteDefinition)
      none = {} of String => String
      list_of_routes = [] of RouteDefinition
      RESOURCES.each_with_index do |resource, index|
        key_rule = ROTATING_RULES[index % ROTATING_RULES.size]
        child_rule = ROTATING_RULES[(index + 3) % ROTATING_RULES.size]
        list_of_routes << RouteDefinition.new("get", "/#{resource}", none)
        list_of_routes << RouteDefinition.new("get", "/#{resource}/new", none)
        list_of_routes << RouteDefinition.new("get", "/#{resource}/:id", {"id" => "numeric"})
        list_of_routes << RouteDefinition.new("get", "/#{resource}/:id/edit", {"id" => "numeric"})
        list_of_routes << RouteDefinition.new("put", "/#{resource}/:id", {"id" => "numeric"})
        list_of_routes << RouteDefinition.new("delete", "/#{resource}/:id", {"id" => "numeric"})
        list_of_routes << RouteDefinition.new("get", "/#{resource}/by/:key", {"key" => key_rule})
        list_of_routes << RouteDefinition.new("get", "/#{resource}/:id/children/:child_key",
          {"id" => "numeric", "child_key" => child_rule})
      end
      list_of_routes
    end

    # Builds the route set for *list_of_routes* with *rules* (label to rule)
    # standing in for each rule label. The payload is the route's index.
    def self.build(list_of_routes : Array(RouteDefinition),
                   rules : Hash(String, Amber::Router::ParamConstraint)) : Amber::Router::RouteSet(Int32)
      route_set = Amber::Router::RouteSet(Int32).new
      list_of_routes.each_with_index do |route, index|
        constraints = route.rule_labels.transform_values { |label| rules[label] }
        route_set.add("#{route.verb}#{route.path}", index, constraints)
      end
      route_set
    end

    # Returns the requests for *list_of_routes*: every fixed route once,
    # every constrained route once with segments its rules accept and once
    # with a segment its last rule rejects (failing on the last byte), and
    # one unknown path per ten routes.
    def self.requests(list_of_routes : Array(RouteDefinition)) : Array(RouteRequest)
      list_of_requests = [] of RouteRequest
      list_of_routes.each do |route|
        next if route.path.includes?('*')
        if route.rule_labels.empty?
          next if route.path.includes?(':')
          list_of_requests << RouteRequest.new(route.verb, route.path, "fixed")
          next
        end
        list_of_requests << RouteRequest.new(route.verb, fill(route, failing_parameter: nil), "rule_hit")
        last_parameter = route.rule_labels.keys.last
        list_of_requests << RouteRequest.new(route.verb, fill(route, failing_parameter: last_parameter), "rule_miss")
      end
      (list_of_routes.size // 10).times do |index|
        list_of_requests << RouteRequest.new("get", "/missing#{index}/#{index}", "unknown")
      end
      list_of_requests
    end

    private def self.fill(route : RouteDefinition, failing_parameter : String?) : String
      route.path.split('/').map do |segment|
        if segment.starts_with?(':')
          parameter = segment.lchop(':')
          if label = route.rule_labels[parameter]?
            samples = SEGMENT_SAMPLES[label]
            parameter == failing_parameter ? samples.failing_late : samples.matching
          else
            "someone"
          end
        else
          segment
        end
      end.join('/')
    end
  end
end
