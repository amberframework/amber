module Amber::DSL::Server
  macro routes(valve, scope = "")
    router.draw {{valve}}, {{scope}} do
      {{yield}}
    end
  end

  macro pipeline(valve)
    handler.build {{valve}} do
      {{yield}}
    end
  end
end
