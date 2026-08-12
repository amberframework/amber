require "../../../spec_helper"

module Amber::Controller::Helpers
  describe AssetHelpers do
    controller = build_controller
    manifest_fixture = File.expand_path("../../../support/assets/manifest.json", __DIR__)

    describe "#image_tag" do
      it "generates an image tag" do
        result = controller.image_tag("/images/logo.png")
        result.should eq "<img src=\"/images/logo.png\" />"
      end

      it "includes alt text" do
        result = controller.image_tag("/images/logo.png", alt: "Company Logo")
        result.should contain "src=\"/images/logo.png\""
        result.should contain "alt=\"Company Logo\""
      end

      it "includes size attributes" do
        result = controller.image_tag("/photo.jpg", width: "200", height: "100")
        result.should contain "width=\"200\""
        result.should contain "height=\"100\""
      end

      it "escapes the src URL" do
        result = controller.image_tag("/images/<script>.png")
        result.should contain "src=\"/images/&lt;script&gt;.png\""
      end

      it "includes additional attributes" do
        result = controller.image_tag("/logo.png", class: "img-responsive", id: "logo")
        result.should contain "class=\"img-responsive\""
        result.should contain "id=\"logo\""
      end
    end

    describe "#stylesheet_link_tag" do
      it "generates a stylesheet link tag with default media" do
        result = controller.stylesheet_link_tag("/css/app.css")
        result.should contain "rel=\"stylesheet\""
        result.should contain "href=\"/css/app.css\""
        result.should contain "media=\"screen\""
        result.should contain "/>"
      end

      it "uses a custom media type" do
        result = controller.stylesheet_link_tag("/css/print.css", media: "print")
        result.should contain "media=\"print\""
        # Should not also have the default media="screen"
        result.scan(/media=/).size.should eq 1
      end

      it "includes additional attributes" do
        result = controller.stylesheet_link_tag("/css/app.css", integrity: "sha256-abc")
        result.should contain "integrity=\"sha256-abc\""
      end

      it "escapes the path" do
        result = controller.stylesheet_link_tag("/css/<malicious>.css")
        result.should contain "href=\"/css/&lt;malicious&gt;.css\""
      end
    end

    describe "#javascript_include_tag" do
      it "generates a script tag" do
        result = controller.javascript_include_tag("/js/app.js")
        result.should eq "<script src=\"/js/app.js\"></script>"
      end

      it "includes additional attributes" do
        result = controller.javascript_include_tag("/js/app.js", async: true, defer: true)
        result.should contain "async"
        result.should contain "defer"
      end

      it "escapes the path" do
        result = controller.javascript_include_tag("/js/<malicious>.js")
        result.should contain "src=\"/js/&lt;malicious&gt;.js\""
      end
    end

    describe "#favicon_tag" do
      it "generates a default favicon tag" do
        result = controller.favicon_tag
        result.should eq "<link rel=\"icon\" type=\"image/x-icon\" href=\"/favicon.ico\" />"
      end

      it "generates a favicon tag with custom path" do
        result = controller.favicon_tag("/images/icon.png")
        result.should contain "href=\"/images/icon.png\""
        result.should contain "rel=\"icon\""
        result.should contain "type=\"image/x-icon\""
      end

      it "escapes the path" do
        result = controller.favicon_tag("/icons/<bad>.ico")
        result.should contain "href=\"/icons/&lt;bad&gt;.ico\""
      end
    end

    describe "manifest-backed assets" do
      before_each do
        Amber::Assets.configure(manifest_path: manifest_fixture)
      end

      after_each do
        Amber::Assets.configure
      end

      it "resolves logical image paths" do
        result = controller.image_tag("images/amber-crystal.svg", alt: "Amber crystal")

        result.should contain %(src="/assets/images/amber-crystal-0123456789abcdef0123456789abcdef.svg")
        result.should contain %(alt="Amber crystal")
      end

      it "adds manifest integrity to local styles and scripts" do
        stylesheet = controller.stylesheet_link_tag("stylesheets/app.css")
        javascript = controller.javascript_include_tag("javascript/app.js", type: "module")

        stylesheet.should contain %(href="/assets/stylesheets/app-11112222333344441111222233334444.css")
        stylesheet.should contain %(integrity="sha256-EREiIjMzREQRESIiMzNERBERIiIzM0REEREiIjMzREQ=")
        stylesheet.should contain %(crossorigin="anonymous")
        javascript.should contain %(src="/assets/javascript/app-fedcba9876543210fedcba9876543210.js")
        javascript.should contain %(integrity=)
        javascript.should contain %(type="module")
      end

      it "resolves favicon type and URL from the manifest" do
        result = controller.favicon_tag("images/amber-crystal.svg")

        result.should eq %(<link rel="icon" type="image/svg+xml" href="/assets/images/amber-crystal-0123456789abcdef0123456789abcdef.svg" />)
      end

      it "renders a serialized, manifest-backed import map" do
        result = controller.javascript_importmap_tag(
          {"app" => "javascript/app.js", "remote" => "https://cdn.example.test/pkg.js"},
          preload: ["javascript/app.js"]
        )

        result.should contain %(<link rel="modulepreload" href="/assets/javascript/app-fedcba9876543210fedcba9876543210.js")
        result.should contain %(integrity=)
        result.should contain %(<script type="importmap">{"imports":{"app":"/assets/javascript/app-fedcba9876543210fedcba9876543210.js","remote":"https://cdn.example.test/pkg.js"}}</script>)
      end

      it "escapes script-closing characters in import maps" do
        result = controller.javascript_importmap_tag({"remote</script>" => "https://cdn.example.test/pkg.js"})

        result.should contain "remote\\u003c/script\\u003e"
        result.should_not contain "remote</script>"
      end
    end
  end
end
