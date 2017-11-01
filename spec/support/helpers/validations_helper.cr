module ValidationsHelper
  def params_builder(body = "")
    params = {} of String | Symbol => Amber::Router::ParamsType
    return params if body.empty?

    body.tr("?", "").split("&").each_with_object(params) do |item, params|
      key, value = item.split("=")
      params[key] = value
    end
  end
end
