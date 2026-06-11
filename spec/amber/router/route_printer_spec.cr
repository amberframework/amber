require "../../spec_helper"

module Amber::Router
  describe RoutePrinter do
    describe ".print_routes" do
      it "outputs formatted route table to IO" do
        io = IO::Memory.new
        RoutePrinter.print_routes(io)
        output = io.to_s

        # Should contain the header
        output.should contain("Verb")
        output.should contain("Path")
        output.should contain("Controller#Action")
        output.should contain("Pipe")
        output.should contain("Name")
      end

      it "filters routes by path" do
        # Register a route in the test server for filtering
        router = Amber::Server.router
        handler = ->(_context : HTTP::Server::Context) { }
        route_a = Route.new("GET", "/filter_test_a", handler, :index, :web, Scope.new, "FilterTestAController")
        route_b = Route.new("GET", "/filter_test_b", handler, :index, :web, Scope.new, "FilterTestBController")
        router.add(route_a)
        router.add(route_b)

        io = IO::Memory.new
        RoutePrinter.print_routes(io, filter: "filter_test_a")
        output = io.to_s

        output.should contain("filter_test_a")
        output.should_not contain("filter_test_b")
      end

      it "filters routes by controller name (case-insensitive)" do
        router = Amber::Server.router
        handler = ->(_context : HTTP::Server::Context) { }
        route = Route.new("GET", "/unique_printer_test", handler, :index, :web, Scope.new, "UniquePrinterController")
        router.add(route)

        io = IO::Memory.new
        RoutePrinter.print_routes(io, filter: "uniqueprinter")
        output = io.to_s

        output.should contain("UniquePrinterController")
      end
    end
  end
end
