require "json"
require "uri"

module Amber
  # Runtime access to the build-time static asset manifest.
  #
  # Asset compilation belongs in the build or deploy step. Amber only reads the
  # resulting manifest while serving requests, so production filesystems can be
  # read-only and request latency never includes asset generation.
  module Assets
    DEFAULT_MANIFEST_PATH = "public/assets/manifest.json"

    class Error < Exception
    end

    class ManifestNotFound < Error
      def initialize(path : String)
        super("Asset manifest not found at #{path.inspect}. Run the asset build before starting the application.")
      end
    end

    class MissingAsset < Error
      getter logical_path : String

      def initialize(@logical_path : String)
        super("Asset #{logical_path.inspect} is missing from the asset manifest. Add the file under app/assets and rebuild assets.")
      end
    end

    class InvalidManifest < Error
      def initialize(path : String, detail : String)
        super("Asset manifest at #{path.inspect} is invalid: #{detail}")
      end
    end

    class Entry
      include JSON::Serializable

      getter path : String
      getter digest : String
      getter integrity : String
      getter content_type : String
      getter bytes : Int64

      def initialize(
        @path : String,
        @digest : String,
        @integrity : String,
        @content_type : String,
        @bytes : Int64,
      )
      end
    end

    class Manifest
      include JSON::Serializable

      getter schema_version : Int32
      getter public_path : String
      getter assets : Hash(String, Entry)

      def initialize(
        @schema_version : Int32,
        @public_path : String,
        @assets : Hash(String, Entry),
      )
      end

      def self.load(path : String) : self
        raise ManifestNotFound.new(path) unless File.file?(path)

        manifest = from_json(File.read(path))
        manifest.validate!(path)
        manifest
      rescue ex : JSON::SerializableError | JSON::ParseException
        raise InvalidManifest.new(path, ex.message || ex.class.name)
      end

      def self.load(path : Path) : self
        load(path.to_s)
      end

      def entry(logical_path : String) : Entry
        normalized = Assets.normalize_logical_path(logical_path)
        assets[normalized]? || raise MissingAsset.new(normalized)
      end

      def path(logical_path : String) : String
        entry(logical_path).path
      end

      def integrity(logical_path : String) : String
        entry(logical_path).integrity
      end

      def validate!(source : String = "asset manifest") : Nil
        unless schema_version == 1
          raise InvalidManifest.new(source, "unsupported schema_version #{schema_version}; expected 1")
        end
        unless public_path == Assets.normalize_public_path(public_path)
          raise InvalidManifest.new(source, "public_path must be a normalized root-relative URL path")
        end

        emitted_paths = Set(String).new
        assets.each do |logical_path, entry|
          normalized = Assets.normalize_logical_path(logical_path)
          unless normalized == logical_path
            raise InvalidManifest.new(source, "asset key #{logical_path.inspect} is not normalized")
          end
          unless entry.digest.matches?(/\A[0-9a-f]{64}\z/)
            raise InvalidManifest.new(source, "#{logical_path.inspect} has an invalid SHA-256 digest")
          end
          expected_path = Assets.expected_public_path(normalized, entry.digest, public_path)
          unless entry.path == expected_path
            raise InvalidManifest.new(
              source,
              "#{logical_path.inspect} has noncanonical path #{entry.path.inspect}; expected #{expected_path.inspect}"
            )
          end
          unless entry.integrity.matches?(/\Asha256-[A-Za-z0-9+\/]{43}=\z/)
            raise InvalidManifest.new(source, "#{logical_path.inspect} has an invalid integrity value")
          end
          if entry.content_type.empty? || entry.bytes < 0
            raise InvalidManifest.new(source, "#{logical_path.inspect} has invalid response metadata")
          end
          unless emitted_paths.add?(entry.path)
            raise InvalidManifest.new(source, "multiple logical assets resolve to #{entry.path.inspect}")
          end
        rescue ex : MissingAsset
          raise InvalidManifest.new(source, ex.message || "invalid logical path")
        end
      end
    end

    @@manifest_path : String = DEFAULT_MANIFEST_PATH
    @@manifest : Manifest?
    @@manifest_modified_at : Time?
    @@mutex = Mutex.new

    def self.manifest_path : String
      @@manifest_path
    end

    # Configures the persisted manifest Amber reads. Relative paths are resolved
    # by the application process, normally from the project root.
    def self.configure(*, manifest_path : String = DEFAULT_MANIFEST_PATH) : Nil
      @@mutex.synchronize do
        @@manifest_path = manifest_path
        @@manifest = nil
        @@manifest_modified_at = nil
      end
    end

    # Clears the cached manifest. This is useful after an in-process development
    # build and in tests; production applications normally never need it.
    def self.reload! : Manifest
      @@mutex.synchronize do
        @@manifest = load_manifest
        @@manifest_modified_at = manifest_mtime
        @@manifest.not_nil!
      end
    end

    def self.manifest : Manifest
      @@mutex.synchronize do
        if @@manifest.nil? || development_manifest_changed?
          @@manifest = load_manifest
          @@manifest_modified_at = manifest_mtime
        end
        @@manifest.not_nil!
      end
    end

    def self.path(logical_path : String) : String
      manifest.path(logical_path)
    end

    def self.integrity(logical_path : String) : String
      manifest.integrity(logical_path)
    end

    def self.entry(logical_path : String) : Entry
      manifest.entry(logical_path)
    end

    # Absolute, protocol, fragment, and data URLs are already public references
    # and remain unchanged. Other values are strict logical manifest keys.
    def self.resolve(path : String) : String
      public_reference?(path) ? path : self.path(path)
    end

    def self.public_reference?(path : String) : Bool
      path.starts_with?('/') ||
        path.starts_with?('#') ||
        path.starts_with?("//") ||
        path.starts_with?("data:") ||
        path.starts_with?("blob:") ||
        path.matches?(/\Ahttps?:/i)
    end

    def self.normalize_logical_path(path : String) : String
      normalized = path.gsub('\\', '/').lchop("./")
      if normalized.empty? || normalized.starts_with?('/') || normalized.includes?('\0')
        raise MissingAsset.new(path)
      end

      parts = [] of String
      normalized.split('/').each do |part|
        next if part.empty? || part == "."
        raise MissingAsset.new(path) if part == ".."
        parts << part
      end

      raise MissingAsset.new(path) if parts.empty?
      parts.join('/')
    end

    def self.normalize_public_path(path : String) : String
      value = path.strip
      if value.empty? || !value.starts_with?('/') || value.starts_with?("//") ||
         value.includes?('\0') || value.includes?('?') || value.includes?('#')
        raise InvalidManifest.new("asset manifest", "public_path must be a root-relative URL path")
      end

      normalized = value.gsub(/\/{2,}/, "/")
      normalized = normalized.rstrip('/') unless normalized == "/"
      segments = normalized.split('/')
      if segments.any? { |segment| segment == "." || segment == ".." }
        raise InvalidManifest.new("asset manifest", "public_path must not traverse directories")
      end
      normalized
    end

    def self.expected_public_path(logical_path : String, digest : String, public_path : String) : String
      extension = File.extname(logical_path)
      stem = extension.empty? ? logical_path : logical_path[0, logical_path.bytesize - extension.bytesize]
      fingerprinted = "#{stem}-#{digest[0, 32]}#{extension}"
      encoded = fingerprinted.split('/').map { |part| URI.encode_path_segment(part) }.join('/')
      public_path == "/" ? "/#{encoded}" : "#{public_path}/#{encoded}"
    end

    private def self.load_manifest : Manifest
      Manifest.load(@@manifest_path)
    end

    private def self.manifest_mtime : Time?
      File.info?(@@manifest_path).try(&.modification_time)
    end

    private def self.development_manifest_changed? : Bool
      Amber.env.development? && @@manifest_modified_at != manifest_mtime
    end
  end
end
