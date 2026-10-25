# Compiled and run by spec/amber/environment/require_time_settings_spec.cr.
#
# It boots the way a generated Amber app does: require Amber, then configure
# the environment and register a custom settings section as
# config/application.cr and config/initializers/*.cr would. Settings must load
# only when this file first reads them, so the registered section and the
# configured path and environment all reach the loaded settings.
require "../../../src/amber"
require "../../../src/amber/testing"

struct RequireTimeProbeConfig
  include YAML::Serializable

  property label : String = "default"

  def initialize
  end
end

config_path = ARGV[0]? || abort("usage: probe_app CONFIG_ENVIRONMENTS_PATH")

ENV["AMBER_ENV"] = "lazy_probe"
Amber.path = config_path
Amber::Configuration.register(:probe, RequireTimeProbeConfig)

loaded_section = Amber.settings.to_app_config.custom_configs["probe"]?
probe_label = loaded_section.as?(RequireTimeProbeConfig).try(&.label) || "MISSING"

STDOUT.puts "env=#{Amber.env}"
STDOUT.puts "name=#{Amber.settings.name}"
STDOUT.puts "probe.label=#{probe_label}"
