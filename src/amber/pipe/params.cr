require "json"

module Amber
  module Pipe
    # The Params handler will parse parameters from a URL, a form post or a JSON
    # post and provide them in the context params hash.  This unifies access to
    # parameters into one place to simplify access to them.
    # Note: other params from the router will be handled in the router handler
    # instead of here.  This removes a dependency on the router in case it is
    # replaced or not needed.
    class Params < Base
      URL_ENCODED_FORM = "application/x-www-form-urlencoded"
      APPLICATION_JSON = "application/json"

      def self.instance
        @@instance ||= new
      end

      def call(context)
        context.clear_params
        parse(context)
        call_next(context)
      end

      def parse(context)
        parse_query(context)
        if content_type = context.request.headers["Content-Type"]?
          parse_body(context) if content_type.match /^#{Regex.escape URL_ENCODED_FORM}/
          parse_json(context) if content_type == APPLICATION_JSON
        end
      end

      def parse_query(context)
        parse_part(context, context.request.query)
      end

      def parse_body(context)
        parse_part(context, context.request.body)
      end

      def parse_json(context)
        if body = context.request.body.not_nil!.gets_to_end
          if body.size > 2
            case json = JSON.parse(body).raw
            when Hash
              json.each do |key, value|
                context.params[key.as(String)] = value.to_s
              end
            when Array
              context.params["_json"] = json.to_s
            end
          end
        end
      end

      private def parse_part(context, part)
        values = case part
                 when IO
                   part.gets_to_end
                 when String
                   part.to_s
                 else
                   ""
                 end

        HTTP::Params.parse(values) do |key, value|
          context.params.add(key, value)
        end
      end
    end
  end
end
