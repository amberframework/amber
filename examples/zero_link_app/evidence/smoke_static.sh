#!/usr/bin/env bash
# Runs the static "after" binary from build_static.sh against PostgreSQL and
# sends it JSON, XML and hostile bodies. The binary runs in a bare Alpine
# container that has no libxml2 installed, so XML is parsed by Mica alone.
#
# Usage: WORK_DIR=<build_static.sh work dir> evidence/smoke_static.sh
# Output: evidence/results/after.smoke.txt
set -euo pipefail

POSTGRES_IMAGE="postgres:17.6-alpine@sha256:ef257d85f76e48da1c64832459b59fcaba1a4dac97bf5d7450c77753542eee94"
RUNTIME_IMAGE="alpine:3.22.2@sha256:4b7ce07002c69e8f3d704a9c5d6fd3053be500b7f1c69fc0d80990c2ad8dd412"
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK_DIR:?set WORK_DIR to the build_static.sh work directory}"
RESULTS="$APP_DIR/evidence/results"
NETWORK="zero-link-smoke"
SECRET_KEY_BASE="$(openssl rand -hex 32)"

cleanup() {
  docker rm -f zero-link-app zero-link-db > /dev/null 2>&1 || true
  docker network rm "$NETWORK" > /dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker network create "$NETWORK" > /dev/null
docker run -d --name zero-link-db --network "$NETWORK" \
  -e POSTGRES_PASSWORD=smoke -e POSTGRES_DB=zero_link_app "$POSTGRES_IMAGE" > /dev/null
until docker exec zero-link-db pg_isready -U postgres -d zero_link_app > /dev/null 2>&1; do sleep 1; done
sed -n '/-- +micrate Up/,/-- +micrate Down/p' "$APP_DIR/db/migrations/20261101000000_create_subscribers.sql" |
  docker exec -i zero-link-db psql -q -U postgres -d zero_link_app > /dev/null

docker run -d --name zero-link-app --network "$NETWORK" \
  -v "$WORK/after/bin/zero_link_app:/app/zero_link_app:ro" \
  -v "$WORK/after/config:/app/config:ro" -w /app \
  -e AMBER_ENV=production -e AMBER_SERVER_SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  -e DATABASE_URL="postgres://postgres:smoke@zero-link-db:5432/zero_link_app" \
  "$RUNTIME_IMAGE" /app/zero_link_app > /dev/null

post() {
  local label="$1" content_type="$2" body="$3"
  local response
  # A raw HTTP/1.1 request through BusyBox nc, so error statuses keep their
  # bodies: prints the status code and the response body.
  response="$(docker run --rm --network "$NETWORK" "$RUNTIME_IMAGE" sh -c '
    printf "POST /api/subscribers HTTP/1.1\r\nHost: zero-link-app\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n%s" \
      "$1" "${#2}" "$2" | nc zero-link-app 3000 |
      awk "NR == 1 { status = \$2 } /^\r?$/ { body = 1; next } body { printf \"%s\", \$0 } END { printf \" %s\", status }"' \
    sh "$content_type" "$body" 2>&1 || true)"
  local status="${response##* }" response_body="${response% *}"
  echo "$label [$content_type] -> $status $response_body"
}

for attempt in $(seq 1 30); do
  if docker run --rm --network "$NETWORK" "$RUNTIME_IMAGE" nc -z zero-link-app 3000 2>/dev/null; then break; fi
  sleep 1
done

{
  echo "runtime image: $RUNTIME_IMAGE (no libxml2 installed: $(docker run --rm "$RUNTIME_IMAGE" sh -c 'ls /usr/lib/libxml2* 2>/dev/null | wc -l') libxml2 files)"
  post "JSON body" "application/json" '{"email_address":"ada@example.com","first_name":"Ada"}'
  post "XML body, same fields" "application/xml" '<subscriber><email_address>grace@example.com</email_address><first_name>Grace</first_name></subscriber>'
  post "XML body, text/xml" "text/xml" '<subscriber><email_address>alan@example.com</email_address></subscriber>'
  post "XML body, invalid email" "application/xml" '<subscriber><email_address>not-an-email</email_address></subscriber>'
  post "XML body, malformed" "application/xml" '<subscriber><email_address>x@example.com</subscriber>'
  post "XML body, external entity" "application/xml" '<!DOCTYPE s [<!ENTITY x SYSTEM "file:///etc/passwd">]><subscriber><email_address>&x;</email_address></subscriber>'
  post "XML body, billion laughs" "application/xml" '<!DOCTYPE s [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;"><!ENTITY c "&b;&b;&b;&b;&b;&b;&b;&b;&b;&b;">]><subscriber><email_address>&c;</email_address></subscriber>'
  post "XHTML body, no parser registered" "application/xhtml+xml" '<subscriber/>'
  echo "rows in subscribers: $(docker exec zero-link-db psql -tA -U postgres -d zero_link_app -c 'select count(*) from subscribers')"
  docker logs zero-link-app > "$RESULTS/after.app.log" 2>&1
  echo "app log: results/after.app.log ($(wc -l < "$RESULTS/after.app.log") lines)"
} | tee "$RESULTS/after.smoke.txt"
