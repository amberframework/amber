
 macro get(path, controller, action)
    instance = {{controller.capitalize.id}}Controller.new
    {% if action %}
        action = ->instance.{{action.id}}
    {% else %}
        action = ->instance.index
    {% end %}
    route = Amber::Route.new(:GET, {{path}}, instance, action)
    Amber::Router.instance.add(route)
end
