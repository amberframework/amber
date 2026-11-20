module SessionHelper
  def create_session_config(store)
    Amber.settings.session = {
      "key"     => "name.session",
      "store"   => store,
      "expires" => 120,
    }
    Amber.settings.session
  end

  # Runs the block with `session.store` set to *store* and the generated
  # app's two-week expiry, then restores the previous session settings.
  def with_session_store(store : String, &)
    previous_session_config = Amber.settings.session_config
    Amber.settings.session = {
      "key"     => "spec.session",
      "store"   => store,
      "expires" => 1_209_600,
      "adapter" => "memory",
    }
    yield
  ensure
    Amber.settings.session = previous_session_config if previous_session_config
  end

  # The process-wide memory session adapter that `store: adapter` uses.
  def shared_memory_session_adapter : Amber::Adapters::MemorySessionAdapter
    Amber::Adapters::AdapterFactory.create_session_adapter("memory").as(Amber::Adapters::MemorySessionAdapter)
  end

  # Sends *context* through the Session and Flash pipes, with *action* as
  # the controller.
  def serve_through_session_and_flash(context : HTTP::Server::Context, &action : HTTP::Server::Context -> Nil) : Nil
    session_pipe = Amber::Pipe::Session.new
    flash_pipe = Amber::Pipe::Flash.new
    session_pipe.next = flash_pipe
    flash_pipe.next = action
    session_pipe.call(context)
  end
end
