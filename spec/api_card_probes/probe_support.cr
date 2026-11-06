require "spec"
require "time"
require "../../src/amber"
require "../../src/amber/testing/testing"

class APICardProbeController < Amber::Controller::Base
  def exposed_legacy_params : Amber::Validators::Params
    legacy_params
  end

  def exposed_params : Amber::Controller::SchemaParamsWrapper | Amber::Validators::Params
    params
  end

  def exposed_raw_params : Amber::Router::Params
    raw_params
  end
end

class APICardProbeRequestHelpers
  include Amber::Testing::RequestHelpers

  def get_response
    get("/api-card-probe")
  end
end

class APICardResponseConsumer
  def merge_cookie_jar(cookie_jar : String, response : Amber::Testing::TestResponse)
    response
  end
end

class APICardProbeJob < Amber::Jobs::Job
  include JSON::Serializable

  property record_id : Int64

  def initialize(@record_id : Int64)
  end

  def perform : Nil
  end
end

class APICardNamedSpecSubject
  def self.value : String
    "ok"
  end
end
