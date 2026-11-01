#!/bin/sh
# Runs inside the pinned Crystal Alpine image with a build's bin/ mounted at
# /bin_out and prints what the binary is and links. Called by
# build_static.sh.
set -eu
cd /bin_out

echo "== readelf -d (dynamic section)"
readelf -d zero_link_app 2>&1 || true
echo "== program interpreter"
readelf -l zero_link_app | grep -i 'interpreter' || echo "none"
echo "== ldd"
ldd zero_link_app 2>&1 || true
echo "== bytes"
stat -c %s zero_link_app
strip -o /tmp/zero_link_app.stripped zero_link_app
echo "== bytes after strip"
stat -c %s /tmp/zero_link_app.stripped
echo "== defined symbols from libxml2 (xml*), liblzma (lzma_*), zlib (deflate*, inflate*)"
nm zero_link_app > /tmp/symbols
echo "xml: $(grep -cE ' [TtDdBbRr] xml[A-Z]' /tmp/symbols || true)"
echo "lzma: $(grep -cE ' [TtDdBbRr] lzma_' /tmp/symbols || true)"
echo "zlib: $(grep -cE ' [TtDdBbRr] (deflate|inflate)' /tmp/symbols || true)"
