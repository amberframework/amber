#!/usr/bin/env bash
# Builds this sample app as a static musl binary twice and records what each
# binary links:
#
#   before  Amber 2.0.0-beta.5, which parses XML request bodies with stdlib
#           XML (libxml2). Manifest and lock: evidence/baseline/.
#   after   Amber with #1414 (XML is opt-in) and the Mica parser registered in
#           config/initializers/request_body_parsers.cr. Manifest and lock:
#           the app's own shard.yml and shard.lock.
#
# Both builds use the official Crystal 1.22.1 Alpine image, pinned by digest,
# with an empty compiler cache and `--static --release --no-debug`. The
# linker writes a map file, whose "Archive member included" section names
# every archive member that went into the binary.
#
# Dependencies are installed on the host first with `shards-alpha install
# --frozen`, which checks each one against its git-tree checksum in the lock;
# the container only compiles.
#
# Usage: evidence/build_static.sh [runs]   (default 1 timed build per variant)
# Output: evidence/results/
set -euo pipefail

IMAGE="crystallang/crystal:1.22.1-alpine@sha256:9beda8a9d4a3659c29d185cc18f3fb9b382421bb6a4a59b8f266a6fb4ccc9f16"
RUNS="${1:-1}"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RESULTS="$APP_DIR/evidence/results"
WORK="${WORK_DIR:-$(mktemp -d)}"

mkdir -p "$RESULTS"

prepare_variant() {
  local variant="$1" dir="$WORK/$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  rsync -a --exclude evidence --exclude lib --exclude bin "$APP_DIR/" "$dir/"
  if [ "$variant" = "before" ]; then
    cp "$APP_DIR/evidence/baseline/shard.yml" "$APP_DIR/evidence/baseline/shard.lock" "$dir/"
    rm "$dir/config/initializers/request_body_parsers.cr"
  fi
  (cd "$dir" && shards-alpha install --frozen > "$RESULTS/$variant.shards.log" 2>&1)
}

build_variant() {
  local variant="$1" run="$2"
  docker run --rm -v "$WORK/$variant:/app" -v "$APP_DIR/evidence/build_in_container.sh:/build_in_container.sh:ro" \
    -w /app "$IMAGE" sh /build_in_container.sh
  local seconds
  seconds="$(cat "$WORK/$variant/bin/build_seconds")"
  echo "$variant run $run: $seconds s" | tee -a "$RESULTS/compile_times.txt"
}

inspect_variant() {
  local variant="$1" bin_dir="$WORK/$1/bin"
  cp "$bin_dir/build.log" "$RESULTS/$variant.build.log"
  docker run --rm -v "$bin_dir:/bin_out" -v "$APP_DIR/evidence/inspect_in_container.sh:/inspect_in_container.sh:ro" \
    "$IMAGE" sh /inspect_in_container.sh > "$RESULTS/$variant.binary.txt"
  cp "$bin_dir/archive_members.txt" "$RESULTS/$variant.archive_members.txt"
  cp "$bin_dir/requested_libraries.txt" "$RESULTS/$variant.requested_libraries.txt"
  shasum -a 256 "$bin_dir/zero_link_app" | awk '{ print $1 }' > "$RESULTS/$variant.binary.sha256"
}

: > "$RESULTS/compile_times.txt"
for variant in before after; do
  prepare_variant "$variant"
  for run in $(seq 1 "$RUNS"); do
    build_variant "$variant" "$run"
  done
  inspect_variant "$variant"
done

{
  echo "image: $IMAGE"
  docker run --rm "$IMAGE" sh -c 'crystal --version; uname -m'
  docker info --format 'docker: {{.ServerVersion}}, {{.NCPU}} CPUs, {{.MemTotal}} bytes of memory'
} > "$RESULTS/environment.txt"
echo "results in $RESULTS"
