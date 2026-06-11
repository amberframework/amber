module Backtracer
  class Configuration
    private IGNORED_LINES_PATTERN =
      /_sigtramp|__crystal_(sigfault_handler|raise)|CallStack|caller:|raise<(.+?)>:NoReturn/

    private ADDR_FORMAT =
      /(?<addr>0x[a-f0-9]+)/i

    LINE_PATTERNS = {
      # Crystal method
      #
      # Examples:
      #
      # - `lib/foo/src/foo/bar.cr:50:7 in '*Foo::Bar#_baz:Foo::Bam'`
      # - `lib/foo/src/foo/bar.cr:29:9 in '*Foo::Bar::bar_by_id<String>:Foo::Bam'`
      # - `/usr/local/Cellar/crystal-lang/0.24.1/src/fiber.cr:114:3 in '*Fiber#run:(IO::FileDescriptor | Nil)'`
      /^(?<file>[^:]+)(?:\:(?<line>\d+)(?:\:(?<col>\d+))?)? in '\*?(?<method>.*?)'(?: at #{ADDR_FORMAT})?$/,

      # Crystal proc
      #
      # Examples:
      #
      # - `~procProc(Nil)@/usr/local/Cellar/crystal-lang/0.24.1/src/http/server.cr:148 at 0x102cee376`
      # - `~procProc(HTTP::Server::Context, String)@lib/kemal/src/kemal/route.cr:11 at 0x102ce57db`
      # - `~procProc(HTTP::Server::Context, (File::PReader | HTTP::ChunkedContent | HTTP::Server::Response | HTTP::Server::Response::Output | HTTP::UnknownLengthContent | HTTP::WebSocket::Protocol::StreamIO | IO::ARGF | IO::Delimited | IO::FileDescriptor | IO::Hexdump | IO::Memory | IO::MultiWriter | IO::Sized | Int32 | OpenSSL::SSL::Socket | String::Builder | Zip::ChecksumReader | Zip::ChecksumWriter | Zlib::Deflate | Zlib::Inflate | Nil))@src/foo/bar/baz.cr:420`
      /^(?<method>~[^@]+)@(?<file>[^:]+)(?:\:(?<line>\d+))(?: at #{ADDR_FORMAT})?$/,

      # Crystal crash
      #
      # Examples:
      #
      # - `[0x1057a9fab] *CallStack::print_backtrace:Int32 +107`
      # - `[0x105798aac] __crystal_sigfault_handler +60`
      # - `[0x7fff9ca0652a] _sigtramp +26`
      # - `[0x105cb35a1] GC_realloc +50`
      # - `[0x1057870bb] __crystal_realloc +11`
      # - `[0x1057d3ecc] *Pointer(UInt8)@Pointer(T)#realloc<Int32>:Pointer(UInt8) +28`
      # - `[0x105965e03] *Foo::Bar#bar!:Nil +195`
      # - `[0x10579f5c1] *naughty_bar:Nil +17`
      # - `[0x10579f5a9] *naughty_foo:Nil +9`
      # - `[0x10578706c] __crystal_main +2940`
      # - `[0x105798128] main +40`
      /^\[#{ADDR_FORMAT}\] \*?(?<method>.*?) \+\d+(?: \((?<times>\d+) times\))?$/,

      # Crystal method (--no-debug)
      #
      # Examples:
      #
      # - `HTTP::Server#handle_client<IO+>:Nil`
      # - `HTTP::Server::RequestProcessor#process<IO+, IO+, IO::FileDescriptor>:Nil`
      # - `Kemal::WebSocketHandler@HTTP::Handler#call_next<HTTP::Server::Context>:(Bool | HTTP::Server::Context | IO+ | Int32 | Nil)`
      # - `__crystal_main`
      /^(?<method>.+?)$/,
    }

    # Path considered as "root" of your project.
    #
    # See `Frame#under_src_path?`
    property src_path : String? = {{ Process::INITIAL_PWD }}

    # Directories to be recognized as part of your app. e.g. if you
    # have an `engines` dir at the root of your project, you may want
    # to set this to something like `/^(src|engines)\//`
    #
    # See `Frame#in_app?`
    property app_dirs_pattern = /^src\//

    # Path pattern matching directories to be recognized as your app modules.
    # Defaults to standard Shards setup (`lib/shard-name/...`).
    #
    # See `Frame#shard_name`
    property modules_path_pattern = /^lib\/(?<name>[^\/]+)\/(?:.+)/

    # Number of lines of code context to return by default, or `nil` for none.
    #
    # See `Frame#context`
    property context_lines : Int32? = 5

    # Array of procs used for filtering backtrace lines before parsing.
    # Each filter is expected to return a string, which is then passed
    # onto the next filter, or ignored althoghether if `nil` is returned.
    getter(line_filters) {
      [
        ->(line : String) { line unless line.matches?(IGNORED_LINES_PATTERN) },
      ] of String -> String?
    }
  end
end
