macro get(resource, controller, action)
    instance = {{controller.capitalize.id}}Controller.new
    {% if action %}
        action = ->instance.{{action.id}}
    {% else %}
        action = ->instance.index
    {% end %}
    route = Amber::Route.new("GET", {{resource}}, instance, action)
    Amber::Pipe::Router.instance.add(route)
end
