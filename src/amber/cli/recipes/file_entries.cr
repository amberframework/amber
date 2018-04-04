require "teeplate"

module Amber::Recipes
  module FileEntries
    def each_file(abs, rel, &block : String, String ->)
      Dir.open(abs) do |d|
        d.each_child do |entry|
          each_file abs, rel, entry, &block
        end
      end
    end

    def each_file(abs, rel, entry, &block : String, String ->)
      rel = rel ? File.join(rel, entry) : entry
      abs = File.join(abs, entry)
      if Dir.exists?(abs)
        each_file abs, rel, &block
      else
        block.call abs, rel
      end
    end

    def pack_liquid(files, abs, rel)
      tpl = Liquid::Template.parse File.new(abs)
      io = tpl.render @ctx.as(Liquid::Context)
      files << ::Teeplate::StringData.new(rel, io.to_s, File.stat(abs).perm)
    rescue ex
      p "failed to process #{abs} - #{ex.message}"
    end

    def pack_blob(files, abs, rel)
      io = IO::Memory.new
      File.open(abs) { |f| IO.copy(f, io) }

      files << ::Teeplate::Base64Data.new(rel, io.size.to_u64, Base64.encode(io), File.stat(abs).perm)
    end

    def collect_files(files)
      @ctx = Liquid::Context.new
      set_context @ctx

      each_file(@template, nil) do |abs, rel|
        # process the filename with liquid
        tpl = Liquid::Template.parse rel
        rel = tpl.render @ctx.as(Liquid::Context)

        if /^(.+)\.lqd$|^(.+)\.liquid$/ =~ rel
          # process the file with liquid
          pack_liquid files, abs, $1
        else
          # pack the file without processing
          pack_blob files, abs, rel
        end
      end
    end

    # Returns collected file entries.
    def file_entries : Array(Teeplate::AsDataEntry)
      @file_entries ||= begin
        files = [] of Teeplate::AsDataEntry
        collect_files files
        files
      end
    end
  end
end
