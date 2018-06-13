module Amber::CLI
  class App < Teeplate::FileTree
    directory "#{__DIR__}/app"
    getter database_name_base

    @name : String
    @database : String
    @database_name_base : String
    @language : String
    @model : String
    @sam : Bool
    @db_url : String
    @author : String
    @email : String
    @github_name : String

    def initialize(@name, @database, @language, @model, @sam)
      @database_name_base = generate_database_name_base
      @author = fetch_author
      @email = fetch_email
      @github_name = fetch_github_name

      @db_url =
        if @database == "pg"
          "postgres://admin:password@db:5432/#{@database_name_base}_development"
        elsif @database == "mysql"
          "mysql://admin:password@db:3306/#{@database_name_base}_development"
        else
          "sqlite3:./db/#{@database_name_base}_development.db"
        end
    end

    def sam?
      @sam
    end

    def wait_for_command
      case @database
      when "pg"
        "while ! nc -q 1 db 5432 </dev/null; do sleep 1; done && "
      when "mysql"
         "while ! nc -q 1 db 3306 </dev/null; do sleep 1; done && "
      else
        ""
      end
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
  end
end
