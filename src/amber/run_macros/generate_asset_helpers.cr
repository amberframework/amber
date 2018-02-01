# Originally inspired by luckyframework.org
require "json"
require "colorize"

class Amber::AssetManifestParser
  MANIFEST_PATH = File.expand_path("./config/webpack/manifest.json")
  MAX_RETRIES   =   0
  RETRY_AFTER   = 0.25

  property retries
  @retries : Int32 = 0

  def self.parse_with_retry
    new.parse_with_retry
  end

  def parse_with_retry
    if manifest_exists?
      parse
    else
      retry_or_log_warning
    end
  end

  private def retry_or_log_warning
    if retries < MAX_RETRIES
      self.retries += 1
      sleep(RETRY_AFTER)
      parse_with_retry
    else
      log_missing_manifest_warning
    end
  end

  private def parse
    manifest_file = File.read(MANIFEST_PATH)
    manifest = JSON.parse(manifest_file)

    manifest.each do |key, value|
      puts %({% ASSET_MANIFEST["#{key.as_s}"] = "#{value.as_s}" %})
    end
  end

  private def manifest_exists?
    File.exists?(MANIFEST_PATH)
  end

  private def log_missing_manifest_warning
    # puts "Manifest at #{MANIFEST_PATH} does not exist".colorize(:red)
    # puts "Make sure you have compiled your assets".colorize(:red)
  end
end

begin
  Amber::AssetManifestParser.parse_with_retry
rescue ex
  puts ex.message.colorize(:red)
  raise ex
end
