module Amber::DSL::Server
  macro routes(valve, scope = "")
    router.draw {{valve}}, {{scope}} do
      {{yield}}
    end
  end

  macro pipeline(*valves)
    {% for valve in valves %}
      handler.build {{valve}} do
        {{yield}}
      end
    {% end %}
  end

  macro namespace(scoped_namespace, value = :web)
    router.draw {{value}}, {{scoped_namespace}} do
      {{yield}}
    end
  end
end
