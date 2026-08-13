#!/usr/bin/env bash
set -euo pipefail

shard_version="$(awk '/^version:/ { print $2; exit }' shard.yml)"
source_version="$(sed -n 's/.*VERSION = "\([^"]*\)".*/\1/p' src/amber/version.cr)"
test "$shard_version" = "2.0.0-beta.5"
test "$source_version" = "$shard_version"

files=(README.md docs/README.md docs/getting-started.md docs/beta-installation.md docs/migration-guide.md RELEASE_NOTES_V2_BETA5.md)
grep -F 'brew install amberframework/amber_cli/amber_cli' docs/beta-installation.md
grep -F 'version: 2.0.0-beta.5' docs/getting-started.md
if grep -R -F 'Process.fork' src; then
  echo "Amber V2 must compile with Crystal's default multithreaded runtime" >&2
  exit 1
fi

# Type-check the public server entry point without starting a listener. The
# runtime condition keeps the call reachable to the compiler.
crystal eval 'require "./src/amber"; Amber::Server.start if ENV["AMBER_COMPILE_SERVER"]?'

if grep -Ein 'crimson-knight/(amber|grant|gemma)|amberframework/amber-cli|brew tap amberframework/amber_cli|brew install amber-cli|brew install amber_cli|branch: v2-dev|docs\.amberframework\.org/amber' "${files[@]}"; then
  echo "Amber beta docs contain a stale install or dependency instruction" >&2
  exit 1
fi

echo "Amber framework beta contract checks passed"
