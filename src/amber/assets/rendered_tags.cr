module Amber
  module Assets
    # The HTML of asset tags already rendered against one manifest.
    #
    # Each `Manifest` owns one, so a manifest reloaded in development starts
    # with an empty set, and a production process renders each tag once and
    # then answers from here without allocating. It holds at most
    # `ENTRY_LIMIT` tags of each kind; past that, tags are rendered on every
    # call, so call sites that pass varying paths cannot grow it without
    # bound.
    #
    # ```
    # tags = Amber::Assets::RenderedTags.new
    # tags.fetch(:stylesheet, "stylesheets/app.css") { "<link ... />" }
    # ```
    class RenderedTags
      ENTRY_LIMIT = 1024

      # Which helper rendered a tag; one path renders differently in each.
      enum Kind
        Image
        Stylesheet
        JavascriptInclude
        Favicon
      end

      @tags = {} of {Kind, String} => String
      @importmaps = {} of {Hash(String, String), Array(String)} => String
      @mutex = Mutex.new

      # Returns the tag rendered for *kind* and *path*, rendering it with the
      # block the first time. A block that raises (for example a path missing
      # from the manifest) stores nothing.
      def fetch(kind : Kind, path : String, & : -> String) : String
        key = {kind, path}
        if tag = @mutex.synchronize { @tags[key]? }
          return tag
        end

        tag = yield
        @mutex.synchronize { @tags[key] = tag if @tags.size < ENTRY_LIMIT }
        tag
      end

      # Returns the import map tag rendered for *imports* and *preload*,
      # rendering it with the block the first time. The stored key is a copy,
      # so a caller that changes its hash or array later changes nothing here.
      def fetch_importmap(imports : Hash(String, String), preload : Array(String), & : -> String) : String
        if tag = @mutex.synchronize { @importmaps[{imports, preload}]? }
          return tag
        end

        tag = yield
        @mutex.synchronize do
          @importmaps[{imports.dup, preload.dup}] = tag if @importmaps.size < ENTRY_LIMIT
        end
        tag
      end

      # How many tags are stored, of every kind.
      def size : Int32
        @mutex.synchronize { @tags.size + @importmaps.size }
      end
    end
  end
end
