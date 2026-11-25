#!/bin/bash
# Makes a throwaway CA, intermediate CA and localhost leaf (P-256) in $1 for
# spec/amber/ssl/tls_opt_in_spec.cr: ca.pem, localhost_chain.pem (leaf first)
# and localhost_private_key.pem. Run at spec time, so no private key is
# committed. Needs the openssl command-line tool (OpenSSL 3 or LibreSSL).
set -euo pipefail
D="$1"; W=$(mktemp -d); trap 'rm -rf "$W"' EXIT; cd "$W"
K=pem_k
cat > ext.cnf <<'CNF'
[req]
distinguished_name = dn
[dn]
[root]
basicConstraints = critical,CA:TRUE
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
[intermediate]
basicConstraints = critical,CA:TRUE,pathlen:0
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
[leaf]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost,IP:127.0.0.1
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
CNF
for name in root int leaf; do
  openssl ecparam -name prime256v1 -genkey -noout -out "$name.$K"
done
openssl req -new -x509 -sha256 -key root.$K -out root.pem -days 3650 -subj "/CN=Amber spec root CA" -config ext.cnf -extensions root
openssl req -new -key int.$K -out int.csr -subj "/CN=Amber spec intermediate CA" -config ext.cnf
openssl x509 -req -sha256 -in int.csr -CA root.pem -CAkey root.$K -set_serial 2 -out int.pem -days 3650 -extfile ext.cnf -extensions intermediate
openssl req -new -key leaf.$K -out leaf.csr -subj "/CN=localhost" -config ext.cnf
openssl x509 -req -sha256 -in leaf.csr -CA int.pem -CAkey int.$K -set_serial 3 -out leaf.pem -days 3650 -extfile ext.cnf -extensions leaf
cp root.pem "$D/ca.pem"
cat leaf.pem int.pem > "$D/localhost_chain.pem"
openssl pkcs8 -topk8 -nocrypt -in leaf.$K -out "$D/localhost_private_key.pem"
