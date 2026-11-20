# Turns a router_vs_mica JSON report into Markdown tables.
#
#   /usr/bin/ruby summarize.rb results.json > tables.md
require "json"

report = JSON.parse(File.read(ARGV.fetch(0)))

def estimate(value, digits = 2)
  format("%.#{digits}f [%.#{digits}f, %.#{digits}f]", value["center"], value["low"], value["high"])
end

def verdict(ratio)
  if ratio["high"] < 1.0 then "faster"
  elsif ratio["low"] > 1.0 then "slower"
  else "tie"
  end
end

def table(rows, title)
  puts "### #{title}", ""
  puts "| case | backend | Amber hand ns/call | backend ns/call | ratio backend/hand | verdict | bytes/call hand | bytes/call backend | pairs |"
  puts "|---|---|---|---|---|---|---|---|---|"
  rows.each do |row|
    puts "| #{row["label"]} | #{row["candidate"]} | #{estimate(row["baseline_ns"])} | #{estimate(row["candidate_ns"])} | " \
         "#{estimate(row["ratio"], 3)}x | #{verdict(row["ratio"])} | #{format("%.1f", row["baseline_bytes_per_call"])} | " \
         "#{format("%.1f", row["candidate_bytes_per_call"])} | #{row["pairs"]} |"
  end
  puts
end

puts "Mica commit: #{report["mica_commit"]}; agreement gate: #{report["fuzz_segments_checked"]} segments and " \
     "#{report["fuzz_paths_checked"]} paths, every backend equal to Amber's rules.", ""
table(report["router_results"], "Router lookups (RouteSet#find_span)")
table(report["rule_results"], "Single rule checks (ParamConstraint#matches_span?)")

puts "### One-time compile cost per rule (median of 101)", ""
puts "| rule | backend | microseconds |"
puts "|---|---|---|"
report["compile_costs"].each do |cost|
  puts "| #{cost["label"]} | #{cost["backend"]} | #{format("%.2f", cost["microseconds"])} |"
end
