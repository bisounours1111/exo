#!/usr/bin/env bash
# Generates the internal CA, the registry TLS certificate and the htpasswd file.
# Usage: ./init.sh            (passwords can be overridden with CI_PASSWORD / DEV_PASSWORD)
set -euo pipefail
cd "$(dirname "$0")"
# Git Bash on Windows rewrites "/CN=..." into a Windows path without this.
export MSYS_NO_PATHCONV=1

CI_PASSWORD="${CI_PASSWORD:-ci-push-2024}"
DEV_PASSWORD="${DEV_PASSWORD:-dev-pull-2024}"
HTTPD_IMAGE="httpd:2.4.65-alpine@sha256:07b2fabb7029a0b8aeb2e0fd02651c28fe22c21c5b5a59d6ff5b022791fcd89e"

mkdir -p certs auth

if [[ ! -f certs/ca.key ]]; then
  openssl req -x509 -new -nodes -newkey rsa:4096 -sha256 -days 825 \
    -subj "/O=Shop SAS/CN=Shop SAS Internal CA" \
    -addext "basicConstraints=critical,CA:TRUE,pathlen:0" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -keyout certs/ca.key -out certs/ca.crt
fi

# registry.local for clients, localhost/127.0.0.1 for local tests, gateway for the UI proxy.
cat > certs/registry.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=serverAuth
subjectAltName=DNS:registry.local,DNS:localhost,DNS:gateway,IP:127.0.0.1
EOF
openssl req -new -nodes -newkey rsa:2048 -sha256 \
  -subj "/O=Shop SAS/CN=registry.local" \
  -keyout certs/registry.key -out certs/registry.csr
openssl x509 -req -in certs/registry.csr -CA certs/ca.crt -CAkey certs/ca.key -CAcreateserial \
  -days 397 -sha256 -extfile certs/registry.ext -out certs/registry.crt
rm -f certs/registry.csr certs/registry.ext
# nginx runs as a non-root worker and must be able to read the key through the bind mount.
chmod 644 certs/registry.key

# bcrypt (-B) entries, one per account.
{
  docker run --rm "$HTTPD_IMAGE" htpasswd -Bbn ci "$CI_PASSWORD"
  docker run --rm "$HTTPD_IMAGE" htpasswd -Bbn dev "$DEV_PASSWORD"
} | tr -d '\r' | sed '/^$/d' > auth/htpasswd

openssl x509 -in certs/registry.crt -noout -subject -issuer -ext subjectAltName
echo "htpasswd: $(cut -d: -f1 auth/htpasswd | paste -sd, -)"
