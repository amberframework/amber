#!/usr/bin/env bash
set -euo pipefail

ROLE="${1:?role is required}"
OUTPUT_DIR="${2:-/opt/amber-schema/evidence}"
UNIT="${3:-}"

mkdir -p "$OUTPUT_DIR"
date -u +%Y-%m-%dT%H:%M:%SZ >"$OUTPUT_DIR/${ROLE}-collected-at.txt"
uname -a >"$OUTPUT_DIR/${ROLE}-uname.txt"
lscpu >"$OUTPUT_DIR/${ROLE}-lscpu.txt"
cat /proc/meminfo >"$OUTPUT_DIR/${ROLE}-meminfo.txt"
cat /etc/os-release >"$OUTPUT_DIR/${ROLE}-os-release.txt"

if [[ -n "$UNIT" ]]; then
  systemctl show "$UNIT" \
    --property=ActiveState,SubState,ExecMainPID,CPUUsageNSec,MemoryCurrent,MemoryPeak,TasksCurrent \
    >"$OUTPUT_DIR/${ROLE}-service-accounting.txt"
  journalctl -u "$UNIT" --no-pager >"$OUTPUT_DIR/${ROLE}-service-journal.txt"
  sha256sum /opt/amber-router/bin/schema_contract_http_server >"$OUTPUT_DIR/${ROLE}-binary-sha256.txt"
  ldd /opt/amber-router/bin/schema_contract_http_server >"$OUTPUT_DIR/${ROLE}-binary-ldd.txt"
else
  /usr/local/bin/oha --version >"$OUTPUT_DIR/${ROLE}-oha-version.txt"
  sha256sum /opt/amber-schema/payloads/* >"$OUTPUT_DIR/${ROLE}-payload-sha256.txt"
fi
