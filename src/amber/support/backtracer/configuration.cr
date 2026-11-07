module Backtracer
  class Configuration
    private LIST_OF_IGNORED_LINE_PARTS = {"_sigtramp", "__crystal_sigfault_handler", "__crystal_raise", "CallStack", "caller:"}

    # Returns true for a frame of the exception machinery itself.
    def self.ignored_line?(line : String) : Bool
      return true if LIST_OF_IGNORED_LINE_PARTS.any? { |part| line.includes?(part) }

      raise_index = line.index("raise<")
      raise_index ? !line.index(">:NoReturn", raise_index).nil? : false
    end

    # Path considered as "root" of your project.
    #
    # See `Frame#under_src_path?`
    property src_path : String? = {{ Process::INITIAL_PWD }}

    # Path prefixes of the directories that are part of your app. If you have an
    # `engines` directory at the root of your project, add `"engines/"`.
    #
    # See `Frame#in_app?`
    property list_of_app_directories : Array(String) = ["src/"]

    # Path prefix of the directory that holds shards, `lib/<shard-name>/...`.
    #
    # See `Frame#shard_name`
    property modules_directory : String = "lib/"

    # Number of lines of code context to return by default, or `nil` for none.
    #
    # See `Frame#context`
    property context_lines : Int32? = 5

    # Array of procs used for filtering backtrace lines before parsing.
    # Each filter is expected to return a string, which is then passed
    # onto the next filter, or ignored althoghether if `nil` is returned.
    getter(line_filters) {
      [
        ->(line : String) { line unless Configuration.ignored_line?(line) },
      ] of String -> String?
    }
  end
end
