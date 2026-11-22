#!/usr/bin/env bash
# Checks every regex in this repository against Mica's dialect.
#
# Mica is the default Regex engine of crystal-alpha from 1.21.0-incremental-6.
# It leaves out lookaround, backreferences, atomic groups, possessive
# quantifiers and \K, and a literal that uses one stops the build of every
# app that reaches it. The compiler checks only the literals a program
# reaches; this check reads every file, so a pattern in code no spec calls
# fails here first.
#
# The checker is scripts/check_regex_literals.cr from amberframework/mica,
# fetched at a pinned commit and verified by its Git tree before it runs.
#
# usage: scripts/check_regex_on_mica.sh [DIRECTORY ...]   (default: src spec)
# Set CRYSTAL to choose the compiler. The default is `crystal`, because the
# crystal-alpha wrapper sets its own CRYSTAL_PATH, which hides the checker's
# source; any compiler that honors CRYSTAL_PATH works.
set -euo pipefail

mica_commit=6ff310dfec940f71297388a513a96a16f9aa1b68
mica_tree=2749e2fede02b1f7442d3ffdf7e11bb356009698
mica_repository="${MICA_SOURCE_REPOSITORY:-https://github.com/amberframework/mica.git}"
checkout="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/mica-regex-checker"

mkdir -p "$checkout"
git -C "$checkout" init -q
if git -C "$checkout" remote get-url origin >/dev/null 2>&1; then
  git -C "$checkout" remote set-url origin "$mica_repository"
else
  git -C "$checkout" remote add origin "$mica_repository"
fi
git -C "$checkout" fetch -q --depth=1 origin "$mica_commit"
git -C "$checkout" checkout -q --detach FETCH_HEAD
test "$(git -C "$checkout" rev-parse HEAD)" = "$mica_commit"
test "$(git -C "$checkout" rev-parse 'HEAD^{tree}')" = "$mica_tree"

if [[ -z "${CRYSTAL:-}" ]]; then
  CRYSTAL=crystal
fi

if [[ $# -eq 0 ]]; then
  set -- src spec
fi

CRYSTAL_PATH="$checkout/src:$("$CRYSTAL" env CRYSTAL_PATH)" \
  "$CRYSTAL" run "$checkout/scripts/check_regex_literals.cr" -- "$@"
