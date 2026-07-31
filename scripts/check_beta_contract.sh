#!/usr/bin/env bash
set -euo pipefail

shard_version="$(awk '/^version:/ { print $2; exit }' shard.yml)"
source_version="$(sed -n 's/.*VERSION = "\([^"]*\)".*/\1/p' src/amber/version.cr)"
test "$shard_version" = "2.0.0-beta.1"
test "$source_version" = "$shard_version"

files=(README.md docs/README.md docs/getting-started.md docs/beta-installation.md docs/migration-guide.md RELEASE_NOTES_V2_BETA1.md)
grep -F 'brew tap amberframework/amber_cli' docs/beta-installation.md
grep -F 'brew install amber_cli' docs/beta-installation.md
grep -F 'version: 2.0.0-beta.1' docs/getting-started.md

if grep -Ein 'crimson-knight/(amber|grant|gemma)|amberframework/amber-cli|brew install amber-cli|branch: v2-dev' "${files[@]}"; then
  echo "Amber beta docs contain a stale install or dependency instruction" >&2
  exit 1
fi

echo "Amber framework beta contract checks passed"
