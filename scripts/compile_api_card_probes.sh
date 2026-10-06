#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
probe_directory="$repository_root/spec/api_card_probes"

export CRYSTAL_WORKERS=1
export CRYSTAL_CACHE_DIR="$repository_root/.crystal-cache/api-card-probes"

probe_count=0
error_count=0
warning_count=0

compile_probe() {
  local probe_path="$1"
  shift
  probe_count=$((probe_count + 1))
  if output=$(crystal-alpha build --no-codegen --no-color -Dwithout_mt "$@" "$probe_path" 2>&1); then
    warning_lines=$(printf '%s\n' "$output" | grep -Eic 'warning:' || true)
    warning_count=$((warning_count + warning_lines))
    if (( warning_lines > 0 )); then
      printf 'Warnings in %s:\n%s\n' "${probe_path#"$repository_root"/}" "$output"
    fi
  else
    error_count=$((error_count + 1))
    printf 'Compile error in %s:\n%s\n' "${probe_path#"$repository_root"/}" "$output"
  fi
}

while IFS= read -r probe_path; do
  compile_probe "$probe_path"
done < <(find "$probe_directory" -type f -name '*.cr' ! -name 'probe_support.cr' -print | sort)

if output=$(crystal-alpha spec --no-color -Dwithout_mt "$repository_root/spec/amber/public_api_return_types_spec.cr" 2>&1); then
  warning_lines=$(printf '%s\n' "$output" | grep -Eic 'warning:' || true)
  warning_count=$((warning_count + warning_lines))
  printf '%s\n' "$output"
else
  error_count=$((error_count + 1))
  printf 'Type spec failed:\n%s\n' "$output"
fi

if (( probe_count == 0 )); then
  printf 'Probe compile result: RED (0 probe files found)\n'
  exit 1
elif (( error_count > 0 )); then
  printf 'Probe compile result: RED (errors=%d, warnings=%d, probes=%d)\n' "$error_count" "$warning_count" "$probe_count"
  exit 1
elif (( warning_count > 0 )); then
  printf 'Probe compile result: YELLOW (errors=0, warnings=%d, probes=%d)\n' "$error_count" "$warning_count" "$probe_count"
  exit 1
else
  printf 'Probe compile result: GREEN (errors=0, warnings=0, probes=%d)\n' "$probe_count"
fi
