macro get(resource, controller, handler, valve)
    instance = {{controller.capitalize.id}}Controller.new
    {% if handler %}
        action = ->instance.{{handler.id}}
    {% else %}
        action = ->instance.index
    {% end %}
    route = Amber::Route.new("GET", {{resource}}, instance, action, {{valve}})
    Amber::Pipe::Router.instance.add(route)
end

macro plug(pipe)
	Amber::Pipe::Pipeline.instance.plug {{pipe}}
end