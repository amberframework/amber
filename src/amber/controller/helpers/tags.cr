module Amber::Controller::Helpers
  module Tag
    def csrf_tag
      Amber::Pipe::CSRF.instance.tag(context)
    end
  end
end
