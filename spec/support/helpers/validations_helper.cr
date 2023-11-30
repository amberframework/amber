module ValidationsHelper
  def json_params_builder(body = "")
    request = HTTP::Request.new("POST", "/", HTTP::Headers{"Content-Type" => "application/json"}, body)
    params = Amber::Router::Params.new(request)
  end 

  def params_builder(body = "")
    request = HTTP::Request.new("GET", "")
    params = Amber::Router::Params.new(request)
    return params if body.empty?

    body.tr("?", "").split("&").each_with_object(params) do |item, this_params|
      key, value = item.split("=")
      this_params[key] = value
    end
  end
end
