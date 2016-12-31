require "crustache"

module Kemalyst::Generator
  class Template


    getter name : String
    getter directory : String
    getter templates_path : String

    def initialize(name : String, @directory : String, @templates_path : String)
      if name.match(/\A[a-zA-Z]/)
        @name = name
      else
        raise "Name is not valid."
      end

    end

    def generate(type : String)
      case type
      when "controller", "model", "view"
        path = ["resource", "src", "#{type}s"]
      else
        raise Exception.new "Invalid template type : #{type}"
      end
      output = path[1..-1]
      generate_from_path path, output
    end

    def in_lib?(path)
      path.starts_with?("#{@directory}/lib")
    end

    def relative_path(path)
      path.gsub @directory, ""
    end

    private def generate_from_path(path : Array(String), out_path : Array(String))
      template_path = File.join([@templates_path ] + path)

      if !Dir.exists?(template_path)
        raise Exception.new "Invalid template path."
      end

      puts "Template Path: #{relative_path template_path}"

      # create all directories under template
      Dir.glob("#{template_path}/**/*/") do |dir|
        new_dir = dir.gsub("#{template_path}/", "")
        puts "Creating directory: #{new_dir}"
        to_create = File.join([@directory] + out_path + [new_dir])
        puts "                   TO : #{ relative_path to_create}"
        Dir.mkdir_p(to_create)
      end

      # copy all files under template
      Dir.glob("#{template_path}/**/*") do |file|
        if File.file? file
          new_file = file.gsub("#{template_path}/", "")
          new_file_path = File.join [@directory] + out_path + [new_file]
          puts "Copying template: #{new_file} to #{relative_path new_file_path}"
          File.write(new_file_path, File.read(file).to_s)
        end
      end

      # rename {{name}} files
      Dir.glob("#{@directory}/**/*{{name}}*") do |name_file|
        next if in_lib? name_file
        rename_file = name_file.gsub("{{name}}", @name)
        puts "Renaming template: from #{relative_path name_file} to #{relative_path rename_file}"
        File.rename(name_file, rename_file)
      end

      # process _tmpl files
      Dir.glob("#{@directory}/**/*_tmpl") do |tmpl_file|
        next if in_lib? tmpl_file
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
