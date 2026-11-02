#!/usr/bin/env bash
# Prints what a release publishes for one tag or commit: the commit hash,
# its tree hash, and the sha256 of the source tarball built from it with
# `git archive`. Attach the tarball to the GitHub release as an asset and
# paste the output into the release notes, so an installer can download the
# asset and check its sha256, or compare the tree hash with a checkout.
#
# Usage: scripts/release_checksums.sh v2.0.0-beta.8
set -euo pipefail

ref="${1:?usage: scripts/release_checksums.sh <tag-or-commit>}"
version="${ref#v}"
commit="$(git rev-parse "$ref^{commit}")"
tree="$(git rev-parse "$ref^{tree}")"
tarball="amber-$version.tar.gz"

git archive --format=tar.gz --prefix="amber-$version/" -o "$tarball" "$commit"
sha256="$(shasum -a 256 "$tarball" | awk '{ print $1 }')"

echo "Commit: $commit"
echo "Tree: $tree"
echo "Tarball: $tarball (git archive --format=tar.gz --prefix=amber-$version/ $commit)"
echo "Tarball sha256: $sha256"
