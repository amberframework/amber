# Originally inspired by luckyframework.org
require "colorize"
require "json"
require "levenshtein"

missing_asset = ARGV.first
relative_manifest_path = "./config/webpack/manifest.json"
manifest_path = File.expand_path(relative_manifest_path)
manifest_exists = File.exists?(manifest_path)
if manifest_exists
  manifest_file = File.read(manifest_path)
  manifest = JSON.parse(manifest_file)
  best_match = Levenshtein::Finder.find missing_asset, manifest.map(&.to_s), tolerance: 4
end

if manifest_exists
  puts %("#{missing_asset}" does not exist in the manifest at "#{relative_manifest_path}".).colorize(:red)
else
  puts "In order to use the asset_path(path_to_asset : String) helper, you must have an asset manifest at #{relative_manifest_path}.".colorize(:red)
end

if best_match
  puts %(Did you mean "#{best_match}"?).colorize(:yellow)
else
  puts "Make sure the asset exists and you have compiled your assets".colorize(:red)
end

raise "There was a problem finding the asset"
