module Amber::Controller::Helpers
  module Tag
    def csrf_tag
      Amber::Pipe::CSRF.new.tag(context)
    end
  end
end
