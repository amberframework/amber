module Amber::CLI
  class App < Teeplate::FileTree
    WHICH_GIT_COMMAND = "which git >/dev/null"

    directory "#{__DIR__}/app"
    getter database_name_base

    @name : String
    @database : String
    @database_name_base : String
    @language : String
    @model : String
    @db_url : String
    @wait_for : String
    @author : String
    @email : String
    @github_name : String

    def initialize(@name, @database = "pg", @language = "slang", @model = "granite")
      @db_url = ""
      @wait_for = ""
      @database_name_base = generate_database_name_base
      @author = fetch_author
      @email = fetch_email
      @github_name = fetch_github_name
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end

    private def generate_database_name_base
      @name.gsub('-', '_')
    end

    def fetch_author
      return "[your-name-here]" unless system(WHICH_GIT_COMMAND)
      `git config --get user.name`.strip
    end

    def fetch_email
      return "[your-email-here]" unless system(WHICH_GIT_COMMAND)
      `git config --get user.email`.strip
    end

    def fetch_github_name
      default = "[your-github-name]"
      return default unless system(WHICH_GIT_COMMAND)
      github_user = `git config --get github.user`.strip
      github_user.empty? ? default : github_user
    end
  end
end
