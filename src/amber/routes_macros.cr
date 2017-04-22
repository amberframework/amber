macro get(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("GET", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro post(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("POST", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro _put(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("PUT", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro delete(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("DELETE", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro options(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("OPTIONS", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro head(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("HEAD", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro trace(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("TRACE", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro connect(resource, controller, handler, pipeline)
    instance = {{controller.id}}.new
    action = ->instance.{{handler.id}}
    route = Amber::Route.new("CONNECT", {{resource}}, instance, action, {{pipeline}})
    Amber::Pipe::Router.instance.add(route)
end

macro plug(pipe)
	Amber::Pipe::Pipeline.instance.plug {{pipe}}
end
