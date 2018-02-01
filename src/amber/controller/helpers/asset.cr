# Originally inspired by luckyframework.org
module Amber::Controller::Helpers
  module Asset
    ASSET_MANIFEST = {} of String => String

    {{ run "../../run_macros/generate_asset_helpers" }}

    macro asset_path(path)
      {% if path.is_a?(StringLiteral) %}
        {% if ASSET_MANIFEST[path] %}
          "#{Amber.settings.public_assets_base_path}#{ {{ ASSET_MANIFEST[path] }} }"
        {% else %}
          {{ run "../../run_macros/missing_asset", path }}
        {% end %}
      {% elsif path.is_a?(StringInterpolation) %}
        {% raise <<-ERROR
        \n
        The 'asset' macro doesn't work with string interpolation
        Try this...
          ▸ Use the 'dynamic_asset' method instead
        ERROR %}
      {% else %}
        {% raise <<-ERROR
        \n
        The 'asset' macro requires a literal string like "my-logo.png", instead got: #{path}

        Try this...

          ▸ If you're using a variable, switch to a literal string
          ▸ If you can't use a literal string, use the 'dynamic_asset' method instead

        ERROR %}
      {% end %}
    end

    def dynamic_asset_path(path)
      fingerprinted_path = ASSET_MANIFEST[path]?
      if fingerprinted_path
        Amber.settings.public_assets_base_path + fingerprinted_path
      else
        raise "Missing asset: #{path}"
      end
    end
  end
end
