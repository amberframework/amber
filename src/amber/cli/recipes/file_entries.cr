require "teeplate"

module Amber::Recipes
  module FileEntries
    Log = ::Log.for(self)

    def each_file(absolute_path, filename, &block : String, String ->)
      Dir.open(absolute_path) do |directory|
        directory.each_child do |entry|
          each_file absolute_path, filename, entry, &block
        end
      end
    end

    def each_file(absolute_path, filename, entry, &block : String, String ->)
      filename = filename ? File.join(filename, entry) : entry
      absolute_path = File.join(absolute_path, entry)
      if Dir.exists?(absolute_path)
        each_file absolute_path, filename, &block
      else
        block.call absolute_path, filename
      end
    end

    def pack_liquid(files, absolute_path, filename)
      template = Liquid::Template.parse File.new(absolute_path)
      io = template.render @ctx.as(Liquid::Context)
      files << ::Teeplate::StringData.new(filename, io.to_s, File.info(absolute_path).permissions)
    rescue ex
      Log.error(exception: ex) { "failed to process #{absolute_path}" }
    end

    def pack_blob(files, absolute_path, filename)
      io = IO::Memory.new
      File.open(absolute_path) { |f| IO.copy(f, io) }

      files << ::Teeplate::Base64Data.new(filename, io.size.to_u64, Base64.encode(io), File.info(absolute_path).permissions)
    end

    def collect_files(files)
      if !@template.nil?
        @ctx = Liquid::Context.new
        set_context @ctx

        each_file(@template.as(String), nil) do |absolute_path, filename|
          # process the filename with liquid
          template = Liquid::Template.parse filename
          filename = template.render @ctx.as(Liquid::Context)

          if /^(.+)\.lqd$/ =~ filename || /^(.+)\.liquid$/ =~ filename
            # process the file with liquid
            pack_liquid files, absolute_path, $1
          else
            # pack the file without processing
            pack_blob files, absolute_path, filename
          end
        end
      end
    end

    def file_entries : Array(Teeplate::AsDataEntry)
      @file_entries ||= begin
        files = [] of Teeplate::AsDataEntry
        collect_files files
        files
      end
    end
  end
end
