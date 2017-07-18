module Amber::Controller::Helpers
  module Tag
    def csrf_token
      Amber::Pipe::CSRF.token(context).to_s
    end

    def csrf_tag
      Amber::Pipe::CSRF.tag(context)
    end

    def csrf_metatag
      Amber::Pipe::CSRF.metatag(context)
    end
  end
end
