require "../spec_helper"

describe Amber::Assets do
  fixture = File.expand_path("../support/assets/manifest.json", __DIR__)

  before_each do
    Amber::Assets.configure(manifest_path: fixture)
  end

  after_each do
    Amber::Assets.configure
  end

  it "loads and resolves a persisted production manifest" do
    Amber::Assets.path("images/amber-crystal.svg").should eq "/assets/images/amber-crystal-0123456789abcdef0123456789abcdef.svg"
    Amber::Assets.integrity("stylesheets/app.css").should eq "sha256-EREiIjMzREQRESIiMzNERBERIiIzM0REEREiIjMzREQ="
    Amber::Assets.entry("fonts/amber.woff2").content_type.should eq "font/woff2"
  end

  it "normalizes Windows separators in logical paths" do
    Amber::Assets.path("images\\amber-crystal.svg").should eq "/assets/images/amber-crystal-0123456789abcdef0123456789abcdef.svg"
  end

  it "passes already-public and external references through" do
    references = [
      "/uploads/photo.jpg",
      "https://cdn.example.test/app.css",
      "//cdn.example.test/app.js",
      "data:image/svg+xml;base64,PHN2Zy8+",
      "blob:https://example.test/id",
      "#icon",
    ]

    references.each do |reference|
      Amber::Assets.resolve(reference).should eq reference
    end
  end

  it "does not treat executable URL schemes as public asset references" do
    Amber::Assets.public_reference?("javascript:alert(1)").should be_false
    expect_raises(Amber::Assets::MissingAsset) do
      Amber::Assets.resolve("javascript:alert(1)")
    end
  end

  it "fails clearly when an asset is missing" do
    error = expect_raises(Amber::Assets::MissingAsset, /missing\.png/) do
      Amber::Assets.path("images/missing.png")
    end

    error.message.to_s.should contain "rebuild assets"
  end

  it "rejects paths that can escape the logical asset root" do
    expect_raises(Amber::Assets::MissingAsset) do
      Amber::Assets.path("../secrets.txt")
    end
  end

  it "fails clearly when the manifest was not built" do
    Amber::Assets.configure(manifest_path: "spec/support/assets/does-not-exist.json")

    expect_raises(Amber::Assets::ManifestNotFound, /Run the asset build/) do
      Amber::Assets.manifest
    end
  end

  it "rejects unsupported or unsafe manifest data" do
    invalid_manifest = File.tempname("invalid-asset-manifest", ".json")
    File.write(invalid_manifest, <<-JSON)
      {
        "schema_version": 2,
        "public_path": "/assets",
        "assets": {}
      }
      JSON

    begin
      expect_raises(Amber::Assets::InvalidManifest, /unsupported schema_version/) do
        Amber::Assets::Manifest.load(invalid_manifest)
      end
    ensure
      File.delete?(invalid_manifest)
    end
  end

  it "rejects a noncanonical fingerprinted path" do
    invalid_manifest = File.tempname("invalid-asset-path", ".json")
    contents = File.read(fixture).sub(
      "/assets/images/amber-crystal-0123456789abcdef0123456789abcdef.svg",
      "/assets/images/amber-crystal-not-the-digest.svg"
    )
    File.write(invalid_manifest, contents)

    begin
      expect_raises(Amber::Assets::InvalidManifest, /noncanonical path/) do
        Amber::Assets::Manifest.load(invalid_manifest)
      end
    ensure
      File.delete?(invalid_manifest)
    end
  end
end
