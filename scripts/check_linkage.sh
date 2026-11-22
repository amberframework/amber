#!/usr/bin/env bash
# Checks that a minimal Amber JSON API links no regex engine.
#
# 1. scripts/linkage/minimal_json_app.cr links no libpcre2, and holds no pcre2_ symbol.
# 2. scripts/linkage/regex_control.cr links PCRE2, which proves the check can fail.
# 3. The built app answers its GET route and its POST route with a JSON body,
#    with a malformed Cookie header in the mix, and a GET that answers through
#    `respond_with` with a NamedTuple.
#
# 4. The same app built with -Dwithout_openssl links no libssl and no libcrypto,
#    holds no EVP_, SSL_ or OPENSSL_ symbol, and answers its GET route. The build
#    without the flag links OpenSSL, which proves this check can fail.
#
# 5. The same app built with -Dwithout_zlib links no libz and holds no inflate,
#    deflate or crc32 symbol of it. It answers a GET that accepts gzip with a
#    gzip body that `gzip -dc` expands to the page, and a POST whose body is
#    gzip-encoded with 415. The build without the flag reaches libz, which
#    proves this check can fail.
#
# usage: scripts/check_linkage.sh [OUTPUT_DIR]     (macOS otool, Linux ldd)
# Set CRYSTAL to choose the compiler; `crystal` is the default.
set -euo pipefail
cd "$(dirname "$0")/.."

crystal_compiler=${CRYSTAL:-crystal}
output_directory=${1:-${TMPDIR:-/tmp}/amber-linkage}
probe_port=${LINKAGE_PROBE_PORT:-39127}
mkdir -p "$output_directory"

list_libraries() {
  if [ "$(uname -s)" = "Darwin" ]; then
    otool -L "$1" | tail -n +2 | awk '{print $1}'
  else
    ldd "$1" | awk '{print $1}'
  fi
}

count_pcre2_libraries() {
  list_libraries "$1" | grep -c pcre2 || true
}

count_pcre2_symbols() {
  nm "$1" 2>/dev/null | grep -c pcre2_ || true
}

count_openssl_libraries() {
  list_libraries "$1" | grep -cE 'libssl|libcrypto' || true
}

count_openssl_symbols() {
  nm "$1" 2>/dev/null | grep -cE '[ _](EVP|SSL|OPENSSL)_' || true
}

count_zlib_libraries() {
  list_libraries "$1" | grep -cE 'libz\.' || true
}

count_zlib_symbols() {
  nm "$1" 2>/dev/null | grep -cE '[[:space:]]_?(inflate|deflate|crc32|adler32)(Init2?_|End|Reset)?(@.*)?$' || true
}

"$crystal_compiler" --version | head -1
"$crystal_compiler" build scripts/linkage/minimal_json_app.cr -o "$output_directory/minimal_json_app"
"$crystal_compiler" build scripts/linkage/regex_control.cr -o "$output_directory/regex_control"

"$crystal_compiler" build -Dwithout_openssl scripts/linkage/minimal_json_app.cr -o "$output_directory/minimal_json_app_without_openssl"
"$crystal_compiler" build -Dwithout_zlib scripts/linkage/minimal_json_app.cr -o "$output_directory/minimal_json_app_without_zlib"

echo "minimal_json_app links:"
list_libraries "$output_directory/minimal_json_app" | sed 's/^/  /'

status=0
app_library_count=$(count_pcre2_libraries "$output_directory/minimal_json_app")
app_symbol_count=$(count_pcre2_symbols "$output_directory/minimal_json_app")
if [ "$app_library_count" -ne 0 ] || [ "$app_symbol_count" -ne 0 ]; then
  echo "FAIL: minimal_json_app reaches PCRE2 ($app_library_count libraries, $app_symbol_count symbols)"
  status=1
else
  echo "ok: minimal_json_app links no PCRE2 and holds no pcre2_ symbol"
fi

control_library_count=$(count_pcre2_libraries "$output_directory/regex_control")
control_symbol_count=$(count_pcre2_symbols "$output_directory/regex_control")
if [ "$control_library_count" -eq 0 ] && [ "$control_symbol_count" -eq 0 ]; then
  echo "FAIL: regex_control shows no PCRE2, so this check cannot see it"
  status=1
else
  echo "ok: regex_control reaches PCRE2, so the check can fail"
fi

echo "minimal_json_app built with -Dwithout_openssl links:"
list_libraries "$output_directory/minimal_json_app_without_openssl" | sed 's/^/  /'

flagged_library_count=$(count_openssl_libraries "$output_directory/minimal_json_app_without_openssl")
flagged_symbol_count=$(count_openssl_symbols "$output_directory/minimal_json_app_without_openssl")
if [ "$flagged_library_count" -ne 0 ] || [ "$flagged_symbol_count" -ne 0 ]; then
  echo "FAIL: the -Dwithout_openssl build reaches OpenSSL ($flagged_library_count libraries, $flagged_symbol_count symbols)"
  status=1
else
  echo "ok: the -Dwithout_openssl build links no libssl or libcrypto and holds no EVP_, SSL_ or OPENSSL_ symbol"
fi

default_library_count=$(count_openssl_libraries "$output_directory/minimal_json_app")
default_symbol_count=$(count_openssl_symbols "$output_directory/minimal_json_app")
if [ "$default_library_count" -eq 0 ] && [ "$default_symbol_count" -eq 0 ]; then
  echo "FAIL: the build without the flag shows no OpenSSL, so this check cannot see it"
  status=1
else
  echo "ok: the build without the flag reaches OpenSSL, so the check can fail"
fi

flagged_port=$((probe_port + 1))
LINKAGE_PROBE_PORT="$flagged_port" "$output_directory/minimal_json_app_without_openssl" > "$output_directory/minimal_json_app_without_openssl.log" 2>&1 &
flagged_process_id=$!
for _ in $(seq 1 50); do
  curl --silent --output /dev/null --max-time 1 "http://127.0.0.1:$flagged_port/notes" && break
  sleep 0.1
done
flagged_answer=$(curl --silent --max-time 5 "http://127.0.0.1:$flagged_port/notes" || true)
kill "$flagged_process_id" 2>/dev/null || true
if [ "$flagged_answer" = '{"ok":true}' ]; then
  echo "ok: the -Dwithout_openssl build answers GET"
else
  echo "FAIL: the -Dwithout_openssl build answered [$flagged_answer]"
  tail -20 "$output_directory/minimal_json_app_without_openssl.log"
  status=1
fi

echo "minimal_json_app built with -Dwithout_zlib links:"
list_libraries "$output_directory/minimal_json_app_without_zlib" | sed 's/^/  /'

zlib_free_library_count=$(count_zlib_libraries "$output_directory/minimal_json_app_without_zlib")
zlib_free_symbol_count=$(count_zlib_symbols "$output_directory/minimal_json_app_without_zlib")
if [ "$zlib_free_library_count" -ne 0 ] || [ "$zlib_free_symbol_count" -ne 0 ]; then
  echo "FAIL: the -Dwithout_zlib build reaches libz ($zlib_free_library_count libraries, $zlib_free_symbol_count symbols)"
  status=1
else
  echo "ok: the -Dwithout_zlib build links no libz and holds no inflate, deflate or crc32 symbol"
fi

default_zlib_library_count=$(count_zlib_libraries "$output_directory/minimal_json_app")
default_zlib_symbol_count=$(count_zlib_symbols "$output_directory/minimal_json_app")
if [ "$default_zlib_library_count" -eq 0 ] && [ "$default_zlib_symbol_count" -eq 0 ]; then
  echo "FAIL: the build without the flag shows no libz, so this check cannot see it"
  status=1
else
  echo "ok: the build without the flag reaches libz, so the check can fail"
fi

zlib_free_port=$((probe_port + 2))
LINKAGE_PROBE_PORT="$zlib_free_port" "$output_directory/minimal_json_app_without_zlib" > "$output_directory/minimal_json_app_without_zlib.log" 2>&1 &
zlib_free_process_id=$!
for _ in $(seq 1 50); do
  curl --silent --output /dev/null --max-time 1 "http://127.0.0.1:$zlib_free_port/notes" && break
  sleep 0.1
done
zlib_free_url="http://127.0.0.1:$zlib_free_port"
expected_page=$(for _ in $(seq 1 400); do echo "a line of the long page"; done)
gzip_headers=$(curl --silent --max-time 5 --header 'Accept-Encoding: gzip' --dump-header - --output "$output_directory/long_page.gz" "$zlib_free_url/notes/long" || true)
gzip_page=$(gzip -dc "$output_directory/long_page.gz" 2>/dev/null || true)
gzip_page_bytes=$(wc -c < "$output_directory/long_page.gz" | tr -d ' ')
printf 'title=hi' | gzip -c > "$output_directory/request_body.gz"
encoded_body_status=$(curl --silent --max-time 5 --output /dev/null --write-out '%{http_code}' \
  --header 'Content-Encoding: gzip' --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-binary "@$output_directory/request_body.gz" "$zlib_free_url/notes" || true)
kill "$zlib_free_process_id" 2>/dev/null || true
if echo "$gzip_headers" | grep -qi '^content-encoding: gzip' && [ "$gzip_page" = "$expected_page" ] && [ "$gzip_page_bytes" -lt 1000 ]; then
  echo "ok: the -Dwithout_zlib build answers GET with a gzip body of $gzip_page_bytes bytes that expands to the 9,600-byte page"
else
  echo "FAIL: the -Dwithout_zlib build did not answer GET with the page gzipped ($gzip_page_bytes bytes)"
  echo "$gzip_headers"
  tail -20 "$output_directory/minimal_json_app_without_zlib.log"
  status=1
fi
if [ "$encoded_body_status" = "415" ]; then
  echo "ok: the -Dwithout_zlib build answers a gzip-encoded request body with 415"
else
  echo "FAIL: the -Dwithout_zlib build answered a gzip-encoded request body with [$encoded_body_status]"
  status=1
fi

LINKAGE_PROBE_PORT="$probe_port" "$output_directory/minimal_json_app" > "$output_directory/minimal_json_app.log" 2>&1 &
app_process_id=$!
trap 'kill "$app_process_id" 2>/dev/null || true' EXIT

base_url="http://127.0.0.1:$probe_port"
for _ in $(seq 1 50); do
  curl --silent --output /dev/null --max-time 1 "$base_url/notes" && break
  sleep 0.1
done

get_answer=$(curl --silent --max-time 5 --header 'Cookie: a=1; bad"=2; b="x"; ;;' "$base_url/notes" || true)
post_answer=$(curl --silent --max-time 5 --header 'Content-Type: application/json' --data '{"title":"hi"}' "$base_url/notes" || true)
latest_answer=$(curl --silent --max-time 5 "$base_url/notes/latest" || true)

if [ "$get_answer" = '{"ok":true}' ] && [ "$post_answer" = '{"title":"hi"}' ] && [ "$latest_answer" = '{"title":"latest","count":1}' ]; then
  echo "ok: the app answers GET, POST and the respond_with GET"
else
  echo "FAIL: GET answered [$get_answer], POST answered [$post_answer], respond_with GET answered [$latest_answer]"
  tail -20 "$output_directory/minimal_json_app.log"
  status=1
fi

exit $status
