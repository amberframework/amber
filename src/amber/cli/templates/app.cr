module Amber::CLI
  class App < Teeplate::FileTree
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
      @git_command = which_git_command
    end

    def filter(entries)
      entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
    end

    private def generate_database_name_base
      @name.gsub('-', '_')
    end

    def which_git_command
      system("which git >/dev/null")
    end

    def fetch_author
      default = "[your-name-here]"
      return default unless @git_command
      user_name = `git config --get user.name`.strip
      user_name.empty? ? default : user_name
    end

    def fetch_email
      default = "[your-email-here]"
      return default unless @git_command
      user_email = `git config --get user.email`.strip
      user_email.empty? ? default : user_email
    end

    def fetch_github_name
      default = "[your-github-name]"
      return default unless @git_command
      github_user = `git config --get github.user`.strip
      github_user.empty? ? default : github_user
    end
  end
end
