require "../../spec_helper"
require "json"

# The copy of Beryl under src/amber/vendor is pinned: each file must hold
# the bytes scripts/vendor_into.rb (in the Beryl repository) wrote for the
# commit named in BERYL_VENDORED.json. The copy hashes itself: its SHA-256
# is checked against FIPS vectors in Beryl and against `shasum` by
# scripts/vendor_into.rb --check.
private struct VendoredFile
  include JSON::Serializable

  getter path : String = ""
  getter sha256 : String = ""
end

private struct VendoredManifest
  include JSON::Serializable

  getter source : String = ""
  getter commit : String = ""
  getter namespace : String = ""
  getter list_of_files : Array(VendoredFile) = [] of VendoredFile
end

private VENDOR_ROOT = Path[__DIR__].parent.parent.parent / "src" / "amber" / "vendor"

describe "the vendored copy of Beryl" do
  manifest = VendoredManifest.from_json(File.read(VENDOR_ROOT / "BERYL_VENDORED.json"))

  it "names its source, a full commit and the Amber::Beryl namespace" do
    manifest.source.should eq("https://github.com/amberframework/beryl")
    manifest.commit.size.should eq(40)
    manifest.commit.each_char.all? { |character| character.ascii_number? || ('a'..'f').includes?(character) }.should be_true
    manifest.namespace.should eq("Amber::Beryl")
    manifest.list_of_files.should_not be_empty
  end

  it "holds every pinned file with its pinned sha256" do
    manifest.list_of_files.each do |vendored_file|
      observed_sha256 = Amber::Beryl::Crypto.digest(File.read(VENDOR_ROOT / vendored_file.path)).hexstring
      fail "src/amber/vendor/#{vendored_file.path} does not match its pin" unless observed_sha256 == vendored_file.sha256
    end
  end

  it "holds no file without a pin" do
    list_of_present = Dir.glob((VENDOR_ROOT / "beryl" / "**" / "*.cr").to_s).map { |path| Path[path].relative_to(VENDOR_ROOT).to_s }
    list_of_present << "beryl.cr"
    (list_of_present - manifest.list_of_files.map(&.path)).should be_empty
  end
end
