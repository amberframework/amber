#!/usr/bin/env bash
set -euo pipefail

TARGET_HOST="${TARGET_HOST:?TARGET_HOST is required}"
TARGET_PORT="${TARGET_PORT:-41019}"
PAYLOAD_DIR="${PAYLOAD_DIR:-/opt/amber-schema/payloads}"
RESULT_DIR="${RESULT_DIR:-/opt/amber-schema/results}"
REPETITIONS="${REPETITIONS:-7}"
DURATION="${DURATION:-15s}"
CONNECTIONS="${CONNECTIONS:-16}"
WARMUP_DURATION="${WARMUP_DURATION:-3s}"
OHA_BIN="${OHA_BIN:-/usr/local/bin/oha}"

mkdir -p "$RESULT_DIR"
"$OHA_BIN" --version >"$RESULT_DIR/oha-version.txt"

run_case() {
  local name="$1"
  local output="$2"
  local duration="${3:-$DURATION}"
  local path content_type accept body

  case "$name" in
    json_decode_only)
      path=/bench/json-decode-only
      content_type=application/json
      accept=application/json
      body="$PAYLOAD_DIR/request.json"
      ;;
    validated_json)
      path=/bench/validated
      content_type=application/json
      accept=application/json
      body="$PAYLOAD_DIR/request.json"
      ;;
    validated_cbor)
      path=/bench/validated
      content_type=application/cbor
      accept=application/cbor
      body="$PAYLOAD_DIR/request.cbor"
      ;;
    validated_cose)
      path=/bench/validated
      content_type=application/cose
      accept=application/cose
      body="$PAYLOAD_DIR/request.cose"
      ;;
    *)
      echo "Unknown benchmark case: $name" >&2
      return 2
      ;;
  esac

  "$OHA_BIN" \
    -z "$duration" \
    --wait-ongoing-requests-after-deadline \
    -c "$CONNECTIONS" \
    -m POST \
    -D "$body" \
    -T "$content_type" \
    -A "$accept" \
    --no-tui \
    --output-format json \
    -o "$output" \
    "http://$TARGET_HOST:$TARGET_PORT$path"
}

cases=(json_decode_only validated_json validated_cbor validated_cose)

for name in "${cases[@]}"; do
  run_case "$name" /tmp/amber-schema-warmup.json "$WARMUP_DURATION"
done

for repetition in $(seq 1 "$REPETITIONS"); do
  for offset in 0 1 2 3; do
    index=$(( (repetition - 1 + offset) % 4 ))
    name="${cases[$index]}"
    output="$RESULT_DIR/${name}_r${repetition}.json"
    run_case "$name" "$output"
    rps=$(jq -r '.summary.requestsPerSec' "$output")
    success=$(jq -r '.summary.successRate' "$output")
    echo "DONE repetition=$repetition scenario=$name requests_per_second=$rps success_rate=$success"
  done
done
