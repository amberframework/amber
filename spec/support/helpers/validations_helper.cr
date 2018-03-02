module ValidationsHelper
  def params_builder(body = "")
    request = HTTP::Request.new("GET", "")
    params = Amber::Router::Params.new(request)
    return params if body.empty?

    body.tr("?", "").split("&").each_with_object(params) do |item, params|
      key, value = item.split("=")
      params[key] = value
    end
  end
end
