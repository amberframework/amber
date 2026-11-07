# The gate's control: a program that uses `Regex` at run time. It must link PCRE2,
# so a check that passes it has stopped checking anything.
puts Regex.new(ARGV.first? || "a").matches?("a")
