#!/usr/bin/env bash
set -euo pipefail

SERVER_BIN="${1:-./schema_contract_http_server}"
HOST="${BENCH_HOST:-127.0.0.1}"
PORT="${BENCH_PORT:-41021}"
PAYLOAD_DIR="${BENCH_PAYLOAD_DIR:-/tmp/amber-schema-contract-payloads}"
RESULT_DIR="${BENCH_RESULT_DIR:-benchmarks/results/schema_contract_http_raw}"
REPETITIONS="${BENCH_REPETITIONS:-7}"
DURATION="${BENCH_DURATION:-10s}"
CONNECTIONS="${BENCH_CONNECTIONS:-16}"
OHA_BIN="${OHA_BIN:-/opt/homebrew/bin/oha}"

mkdir -p "$PAYLOAD_DIR" "$RESULT_DIR"
"$SERVER_BIN" --host="$HOST" --port="$PORT" --filler-routes=1000 --emit-payloads="$PAYLOAD_DIR" >"$RESULT_DIR/server.log" 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 100); do
  if grep -q '^READY ' "$RESULT_DIR/server.log"; then
    break
  fi
  sleep 0.05
done
grep '^READY ' "$RESULT_DIR/server.log"

run_case() {
  local name="$1"
  local path="$2"
  local content_type="$3"
  local accept="$4"
  local body="$5"

  "$OHA_BIN" -z 2s -c "$CONNECTIONS" -m POST -D "$body" -T "$content_type" -A "$accept" --no-tui --output-format quiet "http://$HOST:$PORT$path" >/dev/null
  for repetition in $(seq 1 "$REPETITIONS"); do
    "$OHA_BIN" -z "$DURATION" -c "$CONNECTIONS" -m POST -D "$body" -T "$content_type" -A "$accept" --no-tui --output-format json -o "$RESULT_DIR/${name}_r${repetition}.json" "http://$HOST:$PORT$path"
  done
}

run_case json_decode_only /bench/json-decode-only application/json application/json "$PAYLOAD_DIR/request.json"
run_case validated_json /bench/validated application/json application/json "$PAYLOAD_DIR/request.json"
run_case validated_cbor /bench/validated application/cbor application/cbor "$PAYLOAD_DIR/request.cbor"
run_case validated_cose /bench/validated application/cose application/cose "$PAYLOAD_DIR/request.cose"
