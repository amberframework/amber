require "crystal/syntax_highlighter/html"
require "http/cookie"
require "ecr"
require "../../support/backtracer/backtracer"

abstract class ExceptionPage
  module Helpers
    def label_for_frame(frame) : String
      frame.shard_name || begin
        case frame.path
        when nil
          "???"
        when .includes?("/crystal/"), .includes?("/crystal-lang/")
          "crystal"
        else
          "app"
        end
      end
    end

    def css_class_for_frame(frame) : String
      case label_for_frame(frame)
      when "app" then "app"
      when "???" then "unknown"
      else
        "all"
      end
    end
  end

  include Helpers

  def self.new(context : HTTP::Server::Context, exception : Exception)
    new(
      exception,
      context.request.method,
      context.request.path,
      context.response.status,
      nil,
      context.request.query_params,
      context.response.headers,
      context.response.cookies,
      exception.message,
    )
  end

  @method : String
  @path : String
  @status : HTTP::Status
  @title : String
  @params : URI::Params
  @headers : HTTP::Headers
  @cookies : HTTP::Cookies?
  @message : String
  @url : String
  @frames : Array(Backtracer::Backtrace::Frame)

  def initialize(
    exception : Exception,
    @method : String,
    @path : String,
    @status : HTTP::Status,
    title : String? = nil,
    @params : URI::Params = URI::Params.new,
    @headers : HTTP::Headers = HTTP::Headers.new,
    @cookies : HTTP::Cookies = HTTP::Cookies.new,
    message : String? = nil,
    url : String? = nil,
  )
    @title = title || "An Error Occurred: #{@status.description}"
    @message = message || "Something went wrong"
    @url = url || "#{@headers["host"]?}#{@path}"

    @frames = if exception.backtrace?
                Backtracer.parse(exception.backtrace, configuration: backtracer).frames
              else
                [] of Backtracer::Backtrace::Frame
              end
  end

  abstract def styles : Styles

  # Add an optional link to your project
  def project_url : String?
    nil
  end

  # Override this method to add extra HTML to the top of the stack trace heading
  def stack_trace_heading_html
    ""
  end

  # Override this method to add extra javascript to the page
  def extra_javascript
    ""
  end

  # Override this method to provide custom `Backtracer` configuration
  def backtracer : Backtracer::Configuration?
  end

  ECR.def_to_s "#{__DIR__}/exception_page.ecr"
end

require "./styles"
