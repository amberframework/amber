require "uri"

module Amber::Router
  # Provides runtime path and URL helper generation for named routes.
  # Named routes are registered when the `route_name:` parameter is passed
  # to route definitions in the DSL.
  #
  # Usage:
  #   NamedRoutes.path(:user, id: "5")   # => "/users/5"
  #   NamedRoutes.url(:user, id: "5")    # => "http://localhost:3000/users/5"
  #   NamedRoutes.path(:users, page: "2") # => "/users?page=2"
  module NamedRoutes
    # Generates a path string for the given named route, substituting
    # parameter placeholders and appending extra params as query string.
    def self.path(name : Symbol, **params) : String
      route = Amber::Server.router.match_by_name(name)
      raise "No route named :#{name}" unless route

      path_params = {} of String => String
      params.each do |key, value|
        path_params[key.to_s] = value.to_s
      end

      result, remaining = route.substitute_keys_in_path(path_params)

      if remaining && remaining.any?
        query = remaining.map { |k, v| "#{URI.encode_path(k)}=#{URI.encode_path(v)}" }.join("&")
        "#{result}?#{query}"
      else
        result
      end
    end

    # Generates a full URL for the given named route, including scheme, host, and port.
    def self.url(name : Symbol, **params) : String
      host_url = Amber::Server.instance.host_url
      "#{host_url}#{path(name, **params)}"
    end
  end
end
