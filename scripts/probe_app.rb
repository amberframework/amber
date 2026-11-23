# Probes a built Amber app: PCRE2 and GMP linkage, GET /, a form POST /posts with CSRF, gzip,
# refusal of a gzip request body and of a charset=UTF-7 form, and peak RSS under a short load
# at a given GC starting heap. macOS only: it reads otool, nm and /usr/bin/time -l, and
# drives load with oha. The app is `amber new -d sqlite` plus a scaffolded Post with
# `title` and `body` fields, migrated and built with --release.
# docs/guides/performance.md explains how to read the result.
#
#   /usr/bin/ruby scripts/probe_app.rb <app_dir> <binary> <port> <heap_mib>
require "json"
require "open3"
require "net/http"
require "uri"

app_directory, binary_path, port_text, heap_text = ARGV
port = Integer(port_text)
result = { "binary" => binary_path, "bytes" => File.size(binary_path) }

otool_output, = Open3.capture2e("otool", "-L", binary_path)
nm_output, = Open3.capture2e("nm", binary_path)
result["otool_pcre2_lines"] = otool_output.lines.count { |line| line.include?("pcre2") }
result["nm_pcre2_symbols"] = nm_output.lines.count { |line| line.include?("pcre2_") }
result["otool_gmp_lines"] = otool_output.lines.count { |line| line.include?("libgmp") }
result["nm_gmp_symbols"] = nm_output.lines.count { |line| line.include?("__gmp") }

environment = {
  "AMBER_ENV" => "production",
  "AMBER_SERVER_PORT" => port.to_s,
  "AMBER_SERVER_GC_INITIAL_HEAP_MIB" => heap_text,
}
time_log = File.join(app_directory, "time-#{heap_text}.log")
server_log = File.join(app_directory, "server-#{heap_text}.log")
pid = Process.spawn(environment, "/usr/bin/time", "-l", binary_path,
  chdir: app_directory, out: server_log, err: time_log)

base = "http://127.0.0.1:#{port}"
ready = false
60.times do
  begin
    Net::HTTP.get_response(URI("#{base}/"))
    ready = true
    break
  rescue StandardError
    sleep 0.5
  end
end
abort "server never answered; see #{server_log}" unless ready

http = Net::HTTP.new("127.0.0.1", port)
home = http.get("/")
result["get_root_status"] = home.code.to_i
gzip_home = http.get("/", { "Accept-Encoding" => "gzip" })
result["get_root_gzip_content_encoding"] = gzip_home["Content-Encoding"].to_s
result["get_root_vary"] = gzip_home["Vary"].to_s

# Production cookies are Secure, so the probe says it came through an HTTPS proxy.
forwarded = { "X-Forwarded-Proto" => "https" }
form_page = http.get("/posts/new", forwarded)
result["get_new_status"] = form_page.code.to_i
cookie = form_page.get_fields("Set-Cookie").to_a.map { |value| value.split(";").first }.join("; ")
token = form_page.body[/name="_csrf" value="([^"]+)"/, 1]
abort "no CSRF token on /posts/new" unless token
post = Net::HTTP::Post.new("/posts", forwarded)
post["Cookie"] = cookie
post.set_form_data("_csrf" => token, "title" => "Release check", "body" => "probe")
created = http.request(post)
result["post_posts_status"] = created.code.to_i
result["post_posts_location"] = created["Location"].to_s
listing = http.get("/posts")
result["posts_index_shows_new_post"] = listing.body.include?("Release check")

encoded = Net::HTTP::Post.new("/posts")
encoded["Content-Encoding"] = "gzip"
encoded["Content-Type"] = "application/x-www-form-urlencoded"
require "zlib"
encoded.body = Zlib.gzip("title=x")
result["encoded_body_status"] = (Net::HTTP.start("127.0.0.1", port) { |fresh| fresh.request(encoded).code.to_i } rescue "connection closed: #{$!.class}")

# A form that names a charset outside the WHATWG Encoding Standard is refused (amber#1460).
utf7 = Net::HTTP::Post.new("/posts", forwarded)
utf7["Cookie"] = cookie
utf7["Content-Type"] = "application/x-www-form-urlencoded; charset=UTF-7"
utf7.body = URI.encode_www_form("_csrf" => token, "title" => "x", "body" => "y")
result["utf7_form_status"] = (Net::HTTP.start("127.0.0.1", port) { |fresh| fresh.request(utf7).code.to_i } rescue "connection closed: #{$!.class}")

load_output, = Open3.capture2e("oha", "--no-tui", "-z", "15s", "-c", "32", "--output-format", "json", "#{base}/")
load = JSON.parse(load_output) rescue {}
result["get_root_requests_per_second"] = load.dig("summary", "requestsPerSec")&.round
form_output, = Open3.capture2e("oha", "--no-tui", "-z", "15s", "-c", "32", "--output-format", "json", "-H", "X-Forwarded-Proto: https", "#{base}/posts/new")
form_load = JSON.parse(form_output) rescue {}
result["get_posts_new_requests_per_second"] = form_load.dig("summary", "requestsPerSec")&.round

server_pid = `pgrep -P #{pid}`.split.first.to_i
Process.kill("INT", server_pid)
Process.wait(pid)
max_rss_line = File.read(time_log).lines.find { |line| line.include?("maximum resident set size") }
result["peak_rss_bytes"] = max_rss_line.to_s.split.first.to_i
result["peak_rss_mib"] = (result["peak_rss_bytes"] / 1_048_576.0).round(2)
footprint_line = File.read(time_log).lines.find { |line| line.include?("peak memory footprint") }
result["peak_footprint_bytes"] = footprint_line.to_s.split.first.to_i
result["peak_footprint_mib"] = (result["peak_footprint_bytes"] / 1_048_576.0).round(2)
result["heap_mib"] = heap_text.to_i
puts JSON.pretty_generate(result)
