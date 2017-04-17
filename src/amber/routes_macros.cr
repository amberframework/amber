macro get(resource, controller, handler, pipeline)
    instance = {{controller.capitalize.id}}Controller.new
    {% if handler %}
        action = ->instance.{{handler.id}}
    {% else %}
        action = ->instance.index
    {% end %}
    route = Amber::Route.new("GET", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro plug(pipe)
	Amber::Pipe::Pipeline.instance.plug {{pipe}}
end
