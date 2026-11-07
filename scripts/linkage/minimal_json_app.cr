# The smallest Amber JSON API: one GET and one POST with a JSON body, run through
# the default error pipe. `scripts/check_linkage.sh` builds it and checks what it links.
require "../../src/amber"

class NoteInput
  include JSON::Serializable

  property title : String = ""
end

class NotesController < Amber::Controller::Base
  def index
    response.content_type = "application/json"
    %({"ok":true})
  end

  def create
    response.content_type = "application/json"
    request_body = request.body
    note_input = NoteInput.from_json(request_body ? request_body.gets_to_end : "{}")
    {title: note_input.title}.to_json
  end
end

Amber::Server.configure do
  pipeline :api do
    plug Amber::Pipe::Error.new
  end

  routes :api do
    get "/notes", NotesController, :index
    post "/notes", NotesController, :create
  end
end

Amber.settings.host = "127.0.0.1"
Amber.settings.port = ENV.fetch("LINKAGE_PROBE_PORT", "3000").to_i
Amber::Server.start
