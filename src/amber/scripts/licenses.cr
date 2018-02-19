licenses = String.build do |s|
  Dir.glob("./lib/*/LICENSE", "./lib/*/license").each do |path|
    s.puts path.match(/^\.\/lib\/([^\/]+)\//).try(&.[1]).to_s.capitalize
    s.puts "================================================================================"
    s.puts File.read(path)
    s.puts "================================================================================"
    s.puts "\n\n"
  end
end

puts licenses
