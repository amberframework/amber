module Amber::Support::Assets
  CONFIG = {has_loaded_manifest: false}

  macro load_manifest
    {{ run "../run_macros/generate_asset_helpers" }}
    {% CONFIG[:has_loaded_manifest] = true %}
  end
end
