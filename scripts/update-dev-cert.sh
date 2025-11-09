#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${ROOT_DIR}/certs"
DOMAINS_FILE="${ROOT_DIR}/domains.txt"

mkdir -p "${CERT_DIR}"

if [[ ! -f "${DOMAINS_FILE}" ]]; then
  echo "Error: ${DOMAINS_FILE} not found."
  echo "Create it with one domain per line, e.g.:"
  echo "  myapp.test"
  exit 1
fi

# Load domains (ignore blank/comment lines)
mapfile -t DOMAINS < <(grep -Ev '^\s*($|#)' "${DOMAINS_FILE}" || true)

if [[ "${#DOMAINS[@]}" -eq 0 ]]; then
  echo "Error: domains.txt is empty."
  exit 1
fi

PRIMARY_CN="${DOMAINS[0]}"

echo "Using primary CN: ${PRIMARY_CN}"
echo "All SANs: ${DOMAINS[*]}"
echo

# 1) Ensure CA exists (only create if missing)
if [[ ! -f "${CERT_DIR}/local-dev-traefik-ca.crt" || ! -f "${CERT_DIR}/local-dev-traefik-ca.key" ]]; then
  echo "No existing CA found. Creating Local Dev Traefik CA..."

  docker run --rm -v "${CERT_DIR}:/certs" alpine:3 sh -c '
    apk add --no-cache openssl >/dev/null

    openssl req -x509 -nodes -newkey rsa:4096 -days 3650 \
      -keyout /certs/local-dev-traefik-ca.key \
      -out /certs/local-dev-traefik-ca.crt \
      -subj "/CN=Local Dev Traefik CA" \
      -addext "basicConstraints=critical,CA:TRUE" \
      -addext "keyUsage=critical,keyCertSign,cRLSign"
  '

  echo "Created CA: local-dev-traefik-ca.crt"
  echo ">>> Import this CA once into your system/Firefox trust store. <<<"
  echo
else
  echo "Existing CA found. Reusing Local Dev Traefik CA."
fi

# 2) Always (re)generate leaf cert from current domains.txt
echo "Generating dev cert for domains in domains.txt..."

# Clean previous leaf + serial so SAN changes apply cleanly
rm -f "${CERT_DIR}/dev.crt" "${CERT_DIR}/dev.key" "${CERT_DIR}/local-dev-traefik-ca.srl" 2>/dev/null || true

docker run --rm \
  -v "${CERT_DIR}:/certs" \
  -v "${DOMAINS_FILE}:/tmp/domains.txt:ro" \
  alpine:3 sh -c '
    apk add --no-cache openssl >/dev/null

    # Build OpenSSL config
    cat > /tmp/leaf.cnf <<EOF
[ req ]
default_bits       = 2048
prompt             = no
default_md         = sha256
req_extensions     = req_ext
distinguished_name = dn

[ dn ]
CN = '"${PRIMARY_CN}"'

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
EOF

    i=1
    while read -r domain; do
      [ -z "$domain" ] && continue
      case "$domain" in \#*) continue ;; esac
      echo "DNS.$i = $domain" >> /tmp/leaf.cnf
      i=$((i+1))
    done < /tmp/domains.txt

    # Generate key + CSR
    openssl req -new -nodes -newkey rsa:2048 \
      -keyout /certs/dev.key \
      -out /tmp/dev.csr \
      -config /tmp/leaf.cnf

    # Sign using existing CA
    openssl x509 -req -in /tmp/dev.csr -days 3650 \
      -CA /certs/local-dev-traefik-ca.crt \
      -CAkey /certs/local-dev-traefik-ca.key \
      -CAcreateserial \
      -out /certs/dev.crt \
      -extensions req_ext \
      -extfile /tmp/leaf.cnf
'

echo
echo "Updated dev cert:"
echo "  ${CERT_DIR}/dev.crt"
echo "  ${CERT_DIR}/dev.key"
echo
echo "Next:"
echo "  1) If this was the first run, trust local-dev-traefik-ca.crt once."
echo "  2) Restart Traefik: docker compose up -d"
echo "  3) Add new domains to /etc/hosts as needed."
