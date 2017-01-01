module StaticController
  class Index < Kemalyst::Controller
    def call(context)
      render "static/index.slang", "main.slang"
    end
  end
end

