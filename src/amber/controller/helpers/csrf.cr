module Launch::Controller::Helpers
  module CSRF
    def csrf_token
      Launch::Pipe::CSRF.token(context).to_s
    end

    def csrf_tag
      Launch::Pipe::CSRF.tag(context)
    end

    def csrf_metatag
      Launch::Pipe::CSRF.metatag(context)
    end
  end
end
