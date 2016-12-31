require "crustache"

module Kemalyst::Generator
  class Template
    getter name : String
    getter directory : String

    def initialize(name : String, directory : String)
      if name.match(/\A[a-zA-Z]/)
        @name = name
      else
        raise "Name is not valid."
      end

      @directory = File.join(directory)
      unless Dir.exists?(@directory)
        Dir.mkdir_p(@directory)
      end
    end

    def generate(template : String)
      template_path = "#{__DIR__}/../../templates/#{template}"
      puts "Template Path: #{template_path}"

      # create all directories under template
      Dir.glob("#{template_path}/**/*/") do |dir|
        new_dir = dir.gsub("#{template_path}/", "")
        puts "Creating directory: #{new_dir}"
        Dir.mkdir_p("#{@directory}/#{new_dir}")
      end

      # copy all files under template
      Dir.glob("#{template_path}/**/*") do |file|
        if File.file? file
          new_file = file.gsub("#{template_path}/", "")
          puts "Copying template: #{new_file}"
          File.write("#{@directory}/#{new_file}", File.read(file).to_s)
        end
      end

      # rename {{name}} files
      Dir.glob("#{@directory}/**/*{{name}}*") do |name_file|
        rename_file = name_file.gsub("{{name}}", @name)
        puts "Renaming template: #{rename_file}"
        File.rename(name_file, rename_file)
      end

      # process _tmpl files
      Dir.glob("#{@directory}/**/*_tmpl") do |tmpl_file|
        template = Crustache.parse File.read(tmpl_file)
        model = {"name" => name, "Name" => name.capitalize}
        new_file = tmpl_file.gsub("_tmpl", "")
        puts "Processing template: #{new_file}"
        File.write(new_file, String.build { |io|
          #io << Crustache.render template, model
        })
        File.delete tmpl_file
      end
    end
  end
end
