module Amber::Recipes
  class App < Teeplate::FileTree
    include FileEntries

    getter database_name_base
    getter template
    getter recipe

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
    @template : String | Nil
    @recipe : String

    def initialize(@name, @database = "pg", @language = "slang", @model = "granite", @recipe = "base")
      @db_url = ""
      @wait_for = ""
      @database_name_base = generate_database_name_base
      @author = fetch_author
      @email = fetch_email
      @github_name = fetch_github_name
    end

    def fetch_recipe(directory)
      @template = RecipeFetcher.new("app", recipe, directory).fetch
    end

    # setup the Liquid context
    def set_context(ctx)
      return if ctx.nil?

      ctx.set "class_name", class_name
      ctx.set "display_name", display_name
      ctx.set "name", @name
      ctx.set "database", @database
      ctx.set "database_name_base", @database_name_base
      ctx.set "language", @language
      ctx.set "model", @model
      ctx.set "db_url", @db_url
      ctx.set "wait_for", @wait_for
      ctx.set "author", @author
      ctx.set "email", @email
      ctx.set "github_name", @github_name
      ctx.set "recipe", @recipe
      ctx.set "amber_version", Amber::VERSION
      ctx.set "crystal_version", Crystal::VERSION
      ctx.set "urlsafe_base64", Random::Secure.urlsafe_base64(32)
    end

    def isa_view?(entry_path)
      entry_path.includes?(".ecr") || entry_path.includes?(".slang")
    end

    def filter(entries)
      entries.reject { |entry| isa_view?(entry.path) && !entry.path.includes?(".#{@language}") }
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
