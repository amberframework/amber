module Amber::Router
  module RoutePrinter
    # Prints all registered routes to the given IO, optionally filtering
    # by path, controller name, or action name.
    def self.print_routes(io : IO = STDOUT, filter : String? = nil)
      routes = Amber::Server.router.all_routes

      if filter
        filter_downcase = filter.downcase
        routes = routes.select do |route|
          route.path.downcase.includes?(filter_downcase) ||
            route.controller.downcase.includes?(filter_downcase) ||
            route.action.downcase.includes?(filter_downcase)
        end
      end

      io.puts Amber::Server.router.route_table_for(routes)
    end
  end
end
