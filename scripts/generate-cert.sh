#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CERT_DIR="${ROOT_DIR}/certs"

mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

if [[ -f "dev.crt" || -f "dev.key" ]]; then
  echo "dev.crt/dev.key already exist. Delete them first if you want to regenerate."
  exit 1
fi

echo "Generating self-signed wildcard certificate for *.test ..."

docker run --rm -v "$PWD:/certs" alpine/openssl \
  req -x509 -nodes -newkey rsa:2048 -days 3650 \
  -keyout /certs/dev.key -out /certs/dev.crt \
  -subj "/CN=*.test"

echo
echo "Created:"
echo "  ${CERT_DIR}/dev.crt"
echo "  ${CERT_DIR}/dev.key"
echo
echo "Next steps:"
echo "  1) Trust dev.crt in your system certificate store."
echo "  2) Run: docker compose up -d"
