#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${ROOT_DIR}/certs"
DOMAINS_FILE="${ROOT_DIR}/domains.txt"

mkdir -p "${CERT_DIR}"

if [[ ! -f "${DOMAINS_FILE}" ]]; then
  echo "Missing domains.txt in repo root."
  echo "Create it with one hostname per line, e.g.:"
  echo "  floor9design.test"
  exit 1
fi

# Read domains (skip blanks/comments)
mapfile -t DOMAINS < <(grep -Ev '^\s*($|#)' "${DOMAINS_FILE}" || true)

if [[ "${#DOMAINS[@]}" -eq 0 ]]; then
  echo "domains.txt is empty or only comments. Add at least one domain."
  exit 1
fi

if ls "${CERT_DIR}"/dev.* "${CERT_DIR}"/local-dev-traefik-ca.* >/dev/null 2>&1; then
  echo "Existing certs found in ${CERT_DIR}."
  echo "If you want to regenerate from scratch, delete them first:"
  echo "  rm ${CERT_DIR}/dev.* ${CERT_DIR}/local-dev-traefik-ca.*"
  exit 1
fi

PRIMARY_CN="${DOMAINS[0]}"

echo "Using primary CN: ${PRIMARY_CN}"
echo "All SANs: ${DOMAINS[*]}"

echo "Generating Local Dev Traefik CA..."
docker run --rm -v "${CERT_DIR}:/certs" alpine:3 sh -c '
  apk add --no-cache openssl >/dev/null

  openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
    -keyout /certs/local-dev-traefik-ca.key \
    -out /certs/local-dev-traefik-ca.crt \
    -subj "/CN=Local Dev Traefik CA" \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign"
'

echo "Generating leaf cert for domains in domains.txt..."
docker run --rm -v "${CERT_DIR}:/certs" -v "${DOMAINS_FILE}:/tmp/domains.txt:ro" alpine:3 sh -c '
  apk add --no-cache openssl >/dev/null

  # Build OpenSSL config with SANs from domains.txt
  echo "[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
CN = '"${PRIMARY_CN}"'

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]" > /tmp/leaf.cnf

  i=1
  while read -r domain; do
    [ -z "$domain" ] && continue
    case "$domain" in \#*) continue ;; esac
    echo "DNS.$i = $domain" >> /tmp/leaf.cnf
    i=$((i+1))
  done < /tmp/domains.txt

  openssl req -new -nodes -newkey rsa:2048 \
    -keyout /certs/dev.key \
    -out /tmp/dev.csr \
    -config /tmp/leaf.cnf

  openssl x509 -req -in /tmp/dev.csr -days 3650 \
    -CA /certs/local-dev-traefik-ca.crt \
    -CAkey /certs/local-dev-traefik-ca.key \
    -CAcreateserial \
    -out /certs/dev.crt \
    -extensions req_ext \
    -extfile /tmp/leaf.cnf
'

echo
echo "Created:"
echo "  ${CERT_DIR}/local-dev-traefik-ca.crt  (CA root)"
echo "  ${CERT_DIR}/local-dev-traefik-ca.key  (CA key)"
echo "  ${CERT_DIR}/dev.crt                   (SAN cert for: ${DOMAINS[*]})"
echo "  ${CERT_DIR}/dev.key"
echo
echo "Next steps:"
echo "  1) Trust local-dev-traefik-ca.crt as a CA (system + Firefox)."
echo "  2) Ensure /etc/hosts maps those domains to 127.0.0.1."
echo "  3) Start Traefik: docker compose up -d."
