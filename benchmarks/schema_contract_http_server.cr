require "option_parser"
require "../src/amber"

module Amber::Benchmarks::SchemaContractHTTP
  extend self

  REQUEST_ID = "01J8Z3M5N70000000000421987"
  ACCOUNT_ID = "018f1e2d-3c4b-7a69-8f01-000000004219"
  EMAIL      = "performance@example.com"
  NOTE       = "Created from the mobile checkout flow"

  PAYLOAD = {
    "request_id" => JSON::Any.new(REQUEST_ID),
    "account_id" => JSON::Any.new(ACCOUNT_ID),
    "email"      => JSON::Any.new(EMAIL),
    "quantity"   => JSON::Any.new(7_i64),
    "active"     => JSON::Any.new(true),
    "priority"   => JSON::Any.new(3_i64),
    "tags"       => JSON::Any.new([
      JSON::Any.new("mobile"),
      JSON::Any.new("priority"),
      JSON::Any.new("returning"),
    ]),
    "note" => JSON::Any.new(NOTE),
  }

  KEY_PROVIDER = Amber::Schema::COSE::KeyProvider.new(Bytes.new(32, 42_u8), "benchmark-2026-08")

  class RequestContract < Amber::Schema::Definition
    content_type "application/json", "application/cbor", "application/cose"
    additional_properties false

    field :request_id, String, required: true, min_length: 20, max_length: 40
    field :account_id, String, required: true, format: "uuid"
    field :email, String, required: true, format: "email"
    field :quantity, Int32, required: true, min: 1, max: 100
    field :active, Bool, required: true
    field :priority, Int32, required: true, enum: [1, 2, 3]
    field :tags, Array(String), required: true
    field :note, String, required: true, max_length: 200
  end

  class ResponseContract < Amber::Schema::Definition
    content_type "application/json", "application/cbor", "application/cose"
    additional_properties false

    field :request_id, String, required: true
    field :account_id, String, required: true
    field :quantity, Int32, required: true
    field :active, Bool, required: true
    field :tag_count, Int32, required: true
  end

  class BaselineController < Amber::Controller::Base
    def create : Nil
      data = JSON.parse(request.body.not_nil!).as_h
      response_data = acknowledgement(
        data["request_id"].as_s,
        data["account_id"].as_s,
        data["quantity"].as_i,
        data["active"].as_bool,
        data["tags"].as_a.size
      )
      response.status_code = 200
      response.content_type = "application/json"
      response.print response_data.to_json
      response.close
    end

    private def acknowledgement(request_id, account_id, quantity, active, tag_count)
      {
        "request_id" => JSON::Any.new(request_id),
        "account_id" => JSON::Any.new(account_id),
        "quantity"   => JSON::Any.new(quantity),
        "active"     => JSON::Any.new(active),
        "tag_count"  => JSON::Any.new(tag_count),
      }
    end
  end

  class ValidatedController < Amber::Controller::Base
    schema :create, RequestContract
    response_schema :create, ResponseContract, status: 200, description: "Validated acknowledgement"

    def create : Nil
      input = validated_as(RequestContract)
      respond_with({
        "request_id" => JSON::Any.new(input.request_id.not_nil!),
        "account_id" => JSON::Any.new(input.account_id.not_nil!),
        "quantity"   => JSON::Any.new(input.quantity.not_nil!),
        "active"     => JSON::Any.new(input.active.not_nil!),
        "tag_count"  => JSON::Any.new(input.tags.not_nil!.size),
      })
    end
  end

  def controller_handler(controller : T.class, action : Symbol) : HTTP::Server::Context -> forall T
    ->(context : HTTP::Server::Context) do
      instance = controller.new(context)
      instance.run_before_filter(action)
      unless context.content
        instance.create
        instance.run_after_filter(action)
      end
    end
  end

  def add_route(path : String, controller : T.class) : Nil forall T
    Amber::Server.router.add(Amber::Route.new(
      "POST",
      path,
      controller_handler(controller, :create),
      :create,
      :web,
      Amber::Router::Scope.new,
      controller.name
    ))
  end

  def install_routes(filler_routes : Int32) : Nil
    filler_routes.times do |index|
      Amber::Server.router.add(Amber::Route.new(
        "GET",
        "/bench/filler/#{index}/:id",
        ->(context : HTTP::Server::Context) do
          context.response.content_type = "text/plain"
          context.response.print "unused"
          context.response.close
        end,
        :show,
        :web,
        Amber::Router::Scope.new,
        "FillerController"
      ))
    end
    add_route("/bench/json-decode-only", BaselineController)
    add_route("/bench/validated", ValidatedController)
  end

  def emit_payloads(directory : String) : Nil
    Dir.mkdir_p(directory)
    cbor = Amber::Schema::CBOR.encode(PAYLOAD)
    File.write(File.join(directory, "request.json"), PAYLOAD.to_json)
    File.write(File.join(directory, "request.cbor"), cbor)
    File.write(File.join(directory, "request.cose"), Amber::Schema::COSE.encrypt0(cbor, KEY_PROVIDER))
  end

  def run(host : String, port : Int32, filler_routes : Int32, payload_directory : String?) : Nil
    Amber::Schema::COSE.configure(KEY_PROVIDER)
    emit_payloads(payload_directory) if payload_directory
    install_routes(filler_routes)

    pipeline = Amber::Pipe::Pipeline.new
    pipeline.prepare_pipelines
    server = HTTP::Server.new(pipeline)
    address = server.bind_tcp(host, port, false)
    Signal::INT.trap { server.close }
    Signal::TERM.trap { server.close }
    puts "READY #{address} filler_routes=#{filler_routes} scope=full_http_schema_contract"
    STDOUT.flush
    server.listen
  end
end

host = "127.0.0.1"
port = 41021
filler_routes = 1_000
payload_directory = nil.as(String?)

OptionParser.parse do |parser|
  parser.banner = "Usage: schema_contract_http_server [options]"
  parser.on("--host=HOST", "Bind host") { |value| host = value }
  parser.on("--port=PORT", "Bind port") { |value| port = value.to_i }
  parser.on("--filler-routes=COUNT", "Additional routes in the application table") { |value| filler_routes = value.to_i }
  parser.on("--emit-payloads=PATH", "Write matched JSON, CBOR, and COSE request bodies") { |value| payload_directory = value }
end

Amber::Benchmarks::SchemaContractHTTP.run(host, port, filler_routes, payload_directory)
