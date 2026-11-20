require "../../spec_helper"
include SessionHelper

# Bytes the collector still finds in use after two full collections.
private def retained_heap_bytes : Int64
  GC.collect
  GC.collect
  stats = GC.stats
  stats.heap_size.to_i64 - stats.free_bytes.to_i64
end

private def serve_cookieless_get(pipeline : Amber::Pipe::Pipeline, path : String) : HTTP::Server::Context
  context = create_context(HTTP::Request.new("GET", path))
  pipeline.call(context)
  context
end

module Amber::Pipe
  # A visitor that never sends its session cookie back (a load generator, a
  # crawler, a client that ignores cookies) must not leave anything behind on
  # a `:web` route. Before the fix, every such request stored one
  # server-side session of about 400 bytes that lived for two weeks, and the
  # process grew without limit.
  describe "cookieless requests to a :web route" do
    it "keep retained memory flat over 100,000 requests (within 8 MiB) and store no sessions" do
      request_count = 100_000
      retained_growth_limit_bytes = 8_i64 * 1024 * 1024

      with_session_store("adapter") do
        Amber::Server.router.draw :web do
          get "/cookieless/home", HelloController, :world
        end
        pipeline = Pipeline.new
        pipeline.build :web do
          plug Amber::Pipe::Session.new
          plug Amber::Pipe::Flash.new
          plug Amber::Pipe::CSRF.new
        end
        pipeline.prepare_pipelines

        # Warm up, so one-time allocations are not counted as growth.
        1_000.times { serve_cookieless_get(pipeline, "/cookieless/home") }
        sessions_before = shared_memory_session_adapter.size
        retained_before = retained_heap_bytes

        request_count.times do
          context = serve_cookieless_get(pipeline, "/cookieless/home")
          context.response.headers.has_key?("Set-Cookie").should be_false
        end

        retained_growth = retained_heap_bytes - retained_before
        shared_memory_session_adapter.size.should eq sessions_before
        retained_growth.should be < retained_growth_limit_bytes
      end
    end
  end
end
