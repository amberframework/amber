#!/bin/bash
# Makes a throwaway CA, intermediate CA and localhost leaf (P-256) in $1 for
# spec/amber/ssl/tls_opt_in_spec.cr: ca.pem, localhost_chain.pem (leaf first)
# and localhost_private_key.pem. Run at spec time, so no private key is
# committed. Needs the openssl command-line tool.
set -euo pipefail
D="$1"; W=$(mktemp -d); cd "$W"
K=pem_k
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout root.$K -out root.pem -days 3650 -subj "/CN=Amber spec root CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout int.$K -out int.csr -subj "/CN=Amber spec intermediate CA" 2>/dev/null
printf "basicConstraints=critical,CA:TRUE,pathlen:0\nkeyUsage=critical,keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n" > int.ext
openssl x509 -req -in int.csr -CA root.pem -CAkey root.$K -CAcreateserial -out int.pem -days 3650 -extfile int.ext 2>/dev/null
openssl req -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -keyout leaf.$K -out leaf.csr -subj "/CN=localhost" 2>/dev/null
printf "basicConstraints=critical,CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid:always\n" > leaf.ext
openssl x509 -req -in leaf.csr -CA int.pem -CAkey int.$K -CAcreateserial -out leaf.pem -days 3650 -extfile leaf.ext 2>/dev/null
cp root.pem "$D/ca.pem"
cat leaf.pem int.pem > "$D/localhost_chain.pem"
openssl pkcs8 -topk8 -nocrypt -in leaf.$K -out "$D/localhost_private_key.pem"
rm -rf "$W"
