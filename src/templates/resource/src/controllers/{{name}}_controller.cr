require "markdown"
require "../models/demo"

module DemoController
  class Index < Kemalyst::Controller
    def call(context)
      demos = Demo.all
      render "demo/index.ecr", "main.ecr"
    end
  end

  class Show < Kemalyst::Controller
    def call(context)
      id = context.params["id"]
      if demo = Demo.find id
        render "demo/show.ecr", "main.ecr"
      else
        context.flash["warning"] = "Demo with ID #{id} Not Found"
        redirect "/demos"
      end
    end
  end

  class New < Kemalyst::Controller
    def call(context)
      demo = Demo.new
      render "demo/new.ecr", "main.ecr"
    end
  end

  class Create < Kemalyst::Controller
    def call(context)
      demo = Demo.new
      demo.name = context.params["name"]
      demo.description = context.params["description"]

      if demo.valid? && demo.save
        redirect "/demos"
      else
        context.flash["danger"] = "Could not create Demo!"
        render "demo/new.ecr", "main.ecr"
      end
    end
  end

  class Edit < Kemalyst::Controller
    def call(context)
      id = context.params["id"]
      if demo = Demo.find id
        render "demo/edit.ecr", "main.ecr"
      else
        context.flash["warning"] = "Demo with ID #{id} Not Found"
        redirect "/demos"
      end
    end
  end

  class Update < Kemalyst::Controller
    def call(context)
      id = context.params["id"]
      if demo = Demo.find id
        demo.name = context.params["name"]
        demo.description = context.params["description"]

        if demo.valid? && demo.save
          redirect "/demos"
        else
          context.flash["danger"] = "Could not update Demo!"
          render "demo/edit.ecr", "main.ecr"
        end
      else
        context.flash["warning"] = "Demo with ID #{id} Not Found"
        redirect "/demos"
      end
    end
  end

  class Delete < Kemalyst::Controller
    def call(context)
      id = context.params["id"]
      if demo = Demo.find id
        demo.destroy
      else
        context.flash["warning"] = "Demo with ID #{id} Not Found"
      end
      redirect "/demos"
    end
  end
end
