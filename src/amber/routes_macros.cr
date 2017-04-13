
 macro get(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2 %}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}
    {% end %}
    Amber::Router::INSTANCE.add(:GET, {{path}}, action)
end

macro post(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2 %}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}
        Amber::Router::INSTANCE.add(:POST, {{path}}, action)
    {% end %}
end

macro put(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2 %}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}

        Amber::Router::INSTANCE.add(:PUT, path, action)
    {% end %}
end

macro delete(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2 %}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}

        Amber::Router::INSTANCE.add(:DELETE, path, action)
    {% end %}
end

macro patch(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2%}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}

        Amber::Router::INSTANCE.add(:PATCH, path, action)
    {% end %}
end

macro options(path, input)
    {% if input.is_a?(StringLiteral) %}
        {% split = input.split("#") %}
        instance = {{split[0].capitalize.id}}Controller.new

        {% if split.size == 2%}
            action = ->instance.{{split[1].id}}
        {% else %}
            action = ->instance.index
        {% end %}

        Amber::Router::INSTANCE.add(:OPTIONS, path, action)
    {% end %}
end
