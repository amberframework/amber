require "./generator"

module Launch::CLI
  class App < Teeplate::FileTree
    directory "#{__DIR__}/../templates/app"
    getter database_name
    getter adapter_name : String
    @name : String
    @database : String
    @database_name : String
    @language : String
    @model : String
    @db_url : String
    @wait_for : String
    @author : String
    @email : String
    @github_name : String
    @minimal : Bool

    def initialize(@name, @database = "sqlite", @language = "ecr", @minimal = false)
      @db_url = ""
      @wait_for = ""
      @model = "jennifer"
      @database_name = generate_database_name
      @adapter_name = generate_adapter_name
      @author = fetch_author
      @email = fetch_email
      @github_name = fetch_github_name
    end

    def filter(entries)
      entries = entries.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("#{@language}") }
      filter_for_minimal(entries)
    end

    def filter_for_minimal(entries)
      return entries unless @minimal
      filtered = entries.reject { |entry| entry.path.includes?(".js") || entry.path.includes?(".scss") || entry.path.includes?("package.json") ||
        entry.path.includes?("config/webpack") || entry.path.includes?("home_controller") }
      filtered.reject { |entry| entry.path.includes?("src/views") && !entry.path.includes?("mailer") }
    end

    private def generate_database_name
      @name.gsub('-', '_')
    end

    def which_git_command
      system("which git >/dev/null")
    end

    def fetch_author
      if which_git_command
        user_name = `git config --get user.name`.strip
        user_name = nil if user_name.empty?
      end
      user_name || "your-name-here"
    end

    def fetch_email
      if which_git_command
        user_email = `git config --get user.email`.strip
        user_email = nil if user_email.empty?
      end
      user_email || "your-email-here"
    end

    def fetch_github_name
      if which_git_command
        github_user = `git config --get github.user`.strip
        github_user = nil if github_user.empty?
      end
      github_user || "your-github-user"
    end

    def generate_adapter_name
      case @database
      when "pg"
        "postgres"
      when "sqlite"
        "sqlite3"
      when "mysql"
        "mysql"
      else
        @database
      end
    end
  end
end
