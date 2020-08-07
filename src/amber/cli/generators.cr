require "teeplate"
require "random/secure"
require "inflector"

require "./helpers/helpers"
require "./generators/**"

module Amber::CLI
  class Generators
    Log = ::Log.for("generate")

    getter name : String
    getter directory : String
    getter fields : Array(String)

    # Keywords from https://github.com/crystal-lang/crystal/wiki/Crystal-for-Rubyists#available-keywords as of May 6th, 2019
    KEYWORDS = {
      "abstract",
      "do",
      "if",
      "nil?",
      "select",
      "union",
      "alias",
      "else",
      "in",
      "of",
      "self",
      "unless",
      "as",
      "elsif",
      "include",
      "out",
      "sizeof",
      "until",
      "instance_sizeof",
      "as?",
      "pointerof",
      "struct",
      "end",
      "verbatim",
      "asm",
      "ensure",
      "is_a?",
      "private",
      "super",
      "begin",
      "enum",
      "when",
      "lib",
      "protected",
      "then",
      "while",
      "break",
      "extend",
      "macro",
      "require",
      "true",
      "with",
      "case",
      "false",
      "module",
      "rescue",
      "type",
      "yield",
      "class",
      "for",
      "next",
      "responds_to?",
      "typeof",
      "def",
      "fun",
      "nil",
      "return",
      "uninitialized",
      "adler32",
      "argumenterror",
      "array",
      "atomic",
      "base64",
      "benchmark",
      "bigdecimal",
      "bigfloat",
      "bigint",
      "bigrational",
      "bitarray",
      "bool",
      "box",
      "bytes",
      "channel",
      "char",
      "class",
      "colorize",
      "comparable",
      "complex",
      "concurrent",
      "concurrentexecutionexception",
      "crc32",
      "crypto",
      "crystal",
      "csv",
      "debug",
      "deprecated",
      "deque",
      "digest",
      "dir",
      "divisionbyzeroerror",
      "dl",
      "ecr",
      "enum",
      "enumerable",
      "env",
      "errno",
      "exception",
      "fiber",
      "file",
      "fileutils",
      "flags",
      "flate",
      "float",
      "float32",
      "float64",
      "gc",
      "gzip",
      "hash",
      "html",
      "http",
      "indexable",
      "indexerror",
      "ini",
      "int",
      "int128",
      "int16",
      "int32",
      "int64",
      "int8",
      "invalidbigdecimalexception",
      "invalidbytesequenceerror",
      "io",
      "ipsocket",
      "iterable",
      "iterator",
      "json",
      "keyerror",
      "levenshtein",
      "link",
      "llvm",
      "logger",
      "markdown",
      "math",
      "mime",
      "mutex",
      "namedtuple",
      "nil",
      "nilassertionerror",
      "notimplementederror",
      "number",
      "oauth",
      "oauth2",
      "object",
      "openssl",
      "optionparser",
      "overflowerror",
      "partialcomparable",
      "path",
      "pointer",
      "prettyprint",
      "proc",
      "process",
      "random",
      "range",
      "readline",
      "reference",
      "reflect",
      "regex",
      "semanticversion",
      "set",
      "signal",
      "slice",
      "socket",
      "spec",
      "staticarray",
      "string",
      "stringpool",
      "stringscanner",
      "struct",
      "symbol",
      "system",
      "tcpserver",
      "tcpsocket",
      "termios",
      "time",
      "tuple",
      "typecasterror",
      "udpsocket",
      "uint128",
      "uint16",
      "uint32",
      "uint64",
      "uint8",
      "union",
      "unixserver",
      "unixsocket",
      "uri",
      "uuid",
      "valist",
      "value",
      "weakref",
      "xml",
      "yaml",
      "zip",
      "zlib",
    }

    def initialize(name : String, directory : String, fields = [] of String)
      if name.match(/\A[a-zA-Z]/)
        if KEYWORDS.includes?(name.downcase)
          puts "It looks like you may be using a crystal language keyword as a name. This may have unintentional effects."
        end
        @name = name.underscore
      else
        error "Name is not valid."
        exit 1
      end

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end

      @fields = fields
    end

    def generate_app(options)
      info "Rendering App #{name} in #{directory}"
      App.new(name, options.d, options.t, options.minimal?).render(directory, list: true, interactive: !options.assume_yes?, color: options.no_color?)
      unless options.no_deps?
        info "Installing Dependencies"
        Helpers.run("cd #{directory} && shards update")
      end
    end

    def generate(command : String, options)
      if gen_class = Amber::CLI::Generator.registered_commands[command]?
        info "Generating #{gen_class}"
        gen_class.new(name, fields).render(directory, list: true, interactive: !options.assume_yes?, color: options.no_color?)
      else
        error "Generator for #{command} not found"
      end
    end

    def model
      CLI.config.model
    end

    def info(msg)
      Log.info { msg.colorize(:light_cyan) }
    end

    def error(msg)
      Log.error { msg.colorize(:light_red) }
    end
  end
end

class Teeplate::RenderingEntry
  Log = ::Log.for("generate")

  def appends?
    @data.path.includes?("+")
  end

  def forces?
    appends? || @data.forces? || @renderer.forces?
  end

  def local_path
    @local_path ||= if appends?
                      @data.path.gsub("+", "")
                    else
                      @data.path
                    end
  end

  def list(s, color)
    Log.info { s.colorize.fore(color).to_s + local_path }
  end
end

module Teeplate
  abstract class FileTree
    @name_plural : String?
    @class_name : String?
    @display_name : String?
    @display_name_plural : String?

    # Renders all collected file entries.
    #
    # For more information about the arguments, see `Renderer`.
    def render(out_dir, force : Bool = false, interactive : Bool = false, interact : Bool = false, list : Bool = false, color : Bool = false, per_entry : Bool = false, quit : Bool = true)
      renderer = Renderer.new(out_dir, force: force, interact: interactive || interact, list: list, color: color, per_entry: per_entry, quit: quit)
      renderer << filter(file_entries)
      renderer.render
      renderer
    end

    # Override to filter files rendered
    def filter(entries)
      entries
    end

    def name_plural
      @name_plural ||= Inflector.pluralize(@name)
    end

    def class_name
      @class_name ||= @name.camelcase
    end

    def display_name
      @display_name ||= generate_display_name
    end

    def display_name_plural
      @display_name_plural ||= Inflector.pluralize(display_name)
    end

    private def generate_display_name
      @name.underscore.gsub('-', '_').split('_').map(&.capitalize).join(' ')
    end
  end
end
