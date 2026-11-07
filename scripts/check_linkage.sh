#!/usr/bin/env bash
# Checks that a minimal Amber JSON API links no regex engine.
#
# 1. scripts/linkage/minimal_json_app.cr links no libpcre2, and holds no pcre2_ symbol.
# 2. scripts/linkage/regex_control.cr links PCRE2, which proves the check can fail.
# 3. The built app answers its GET route and its POST route with a JSON body,
#    with a malformed Cookie header in the mix.
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

"$crystal_compiler" --version | head -1
"$crystal_compiler" build scripts/linkage/minimal_json_app.cr -o "$output_directory/minimal_json_app"
"$crystal_compiler" build scripts/linkage/regex_control.cr -o "$output_directory/regex_control"

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

if [ "$get_answer" = '{"ok":true}' ] && [ "$post_answer" = '{"title":"hi"}' ]; then
  echo "ok: the app answers GET and POST"
else
  echo "FAIL: GET answered [$get_answer], POST answered [$post_answer]"
  tail -20 "$output_directory/minimal_json_app.log"
  status=1
fi

exit $status
