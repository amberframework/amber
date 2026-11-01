#!/bin/sh
# Runs inside the pinned Crystal Alpine image with the app mounted at /app:
# one static release build from an empty compiler cache, timed, with a
# linker map. Called by build_static.sh.
set -eu
mkdir -p bin
CRYSTAL_CACHE_DIR="$(mktemp -d)"
export CRYSTAL_CACHE_DIR

start=$(date +%s.%N)
if ! crystal build --static --release --no-debug --verbose \
  --link-flags=-Wl,-Map,/app/bin/link.map \
  src/zero_link_app.cr -o bin/zero_link_app > bin/build.log 2>&1; then
  cat bin/build.log
  exit 1
fi
finish=$(date +%s.%N)
echo "$start $finish" | awk '{ printf "%.1f\n", $2 - $1 }' > bin/build_seconds

# The libraries Crystal asked the linker for: the -l flags of its cc line.
grep -E '^cc ' bin/build.log | grep -oE -- ' -l[A-Za-z0-9_+.-]+' | sed 's/^ //' | sort -u > bin/requested_libraries.txt

# The archives the linker took members from, with a member count each, from
# the map's "Archive member included to satisfy reference" section.
awk '/^Archive member included/ { on = 1; next }
     /^(Discarded input sections|Memory Configuration|Allocating common symbols)/ { on = 0 }
     on' bin/link.map |
  grep -oE '[^ ()]+\.a\(' | sed 's/($//' | xargs -n1 basename | sort | uniq -c |
  awk '{ print $2, $1 }' > bin/archive_members.txt
