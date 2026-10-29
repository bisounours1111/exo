#!/usr/bin/env bash
# Shared helpers for the TP03 scripts. Source it: . "$(dirname "$0")/tools.sh"
#
# Each tool (jq, crane, skopeo, syft, trivy, cosign) uses the local binary when installed,
# otherwise a pinned container image. Containers run on the host network with registry.local
# resolved to 127.0.0.1, trust the internal CA and receive the registry credentials.
#
# Environment:
#   REGISTRY           registry host:port            (default registry.local:5000)
#   REGISTRY_USER      account used by the tools      (default ci)
#   REGISTRY_PASSWORD  its password                   (default ci-push-2024)
#   REGISTRY_CA        internal CA certificate        (default starter/registry/certs/ca.crt)

TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${REGISTRY:-registry.local:5000}"
REGISTRY_USER="${REGISTRY_USER:-ci}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-ci-push-2024}"
REGISTRY_CA="${REGISTRY_CA:-$TOOLS_DIR/starter/registry/certs/ca.crt}"

# Docker Desktop on Windows: no path rewriting, and Windows paths for bind mounts.
export MSYS_NO_PATHCONV=1
host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi; }
# Null device usable by native Windows binaries such as curl.exe (\\.\NUL), /dev/null elsewhere.
# shellcheck disable=SC2034 # used by the scripts that source this file
DEVNULL="$(host_path /dev/null)"

JQ_IMAGE="ghcr.io/jqlang/jq:1.8.1@sha256:4f34c6d23f4b1372ac789752cc955dc67c2ae177eb1b5860b75cdc5091ce6f91"
CRANE_IMAGE="gcr.io/go-containerregistry/crane:v0.20.3@sha256:fc86bcad43a000c2a1ca926a1e167db26c053cebc3fa5d14285c72773fb8c11d"
SKOPEO_IMAGE="quay.io/skopeo/stable:v1.20.0@sha256:47853bb9fb24202af9110531ebd6e43c5f97701254ca290596640290d17942f4"
SYFT_IMAGE="anchore/syft:v1.33.0@sha256:f94e5d9fce1f2278491a8e3a63bd5f6ddb81fdfdbb8bf7a1637565c1d5344357"
TRIVY_IMAGE="aquasec/trivy:0.67.2@sha256:e2b22eac59c02003d8749f5b8d9bd073b62e30fefaef5b7c8371204e0a4b0c08"
COSIGN_IMAGE="ghcr.io/sigstore/cosign/cosign:v2.6.1@sha256:68839b7f13dac5a6744a5d8818e984dd39183374e37855c19e14d623d9bc9037"

# Docker config holding only the registry credentials, mounted into the tool containers.
TOOLS_STATE="${TOOLS_STATE:-${TMPDIR:-/tmp}/shop-tp03-tools}"
mkdir -p "$TOOLS_STATE/docker" "$TOOLS_STATE/ca" "$TOOLS_STATE/trivy-cache"
# The same registry is also reachable as localhost:<port> from this machine.
_auth="$(printf '%s:%s' "$REGISTRY_USER" "$REGISTRY_PASSWORD" | base64 | tr -d '\n')"
printf '{"auths":{"%s":{"auth":"%s"},"localhost:%s":{"auth":"%s"}}}\n' \
  "$REGISTRY" "$_auth" "${REGISTRY##*:}" "$_auth" > "$TOOLS_STATE/docker/config.json"
unset _auth
[[ -f "$REGISTRY_CA" ]] && cp "$REGISTRY_CA" "$TOOLS_STATE/ca/shop-ca.crt"

# curl: verify the internal CA; Windows Schannel cannot check revocation for it.
curl_reg() {
  local extra=()
  curl -V 2>/dev/null | grep -q Schannel && extra+=(--ssl-no-revoke)
  curl -sS "${extra[@]}" --cacert "$(host_path "$REGISTRY_CA")" --resolve "${REGISTRY%:*}:${REGISTRY##*:}:127.0.0.1" \
    -u "$REGISTRY_USER:$REGISTRY_PASSWORD" "$@"
}

# Runs a tool image with the working directory mounted on /work.
# SSL_CERT_DIR adds the internal CA to the system roots of Go tools.
_tool_run() {
  local image="$1"; shift
  docker run --rm -i --network host --add-host "${REGISTRY%:*}:127.0.0.1" \
    -v "$(host_path "$PWD"):/work" -w /work \
    -v "$(host_path "$TOOLS_STATE/docker"):/docker-config:ro" -e DOCKER_CONFIG=/docker-config \
    -v "$(host_path "$TOOLS_STATE/ca"):/shop-ca:ro" -e SSL_CERT_DIR=/shop-ca:/etc/ssl/certs \
    -v //var/run/docker.sock:/var/run/docker.sock \
    -e COSIGN_PASSWORD -e COSIGN_YES \
    "${TOOL_EXTRA_ARGS[@]}" "$image" "$@"
}
TOOL_EXTRA_ARGS=()

jq()     { if type -P jq     >/dev/null 2>&1; then command jq "$@";     else docker run --rm -i "$JQ_IMAGE" "$@"; fi; }
crane()  { if type -P crane  >/dev/null 2>&1; then command crane "$@";  else _tool_run "$CRANE_IMAGE" "$@"; fi; }
syft()   { if type -P syft   >/dev/null 2>&1; then command syft "$@";   else _tool_run "$SYFT_IMAGE" "$@"; fi; }
cosign() { if type -P cosign >/dev/null 2>&1; then command cosign "$@"; else _tool_run "$COSIGN_IMAGE" "$@"; fi; }
trivy() {
  if type -P trivy >/dev/null 2>&1; then command trivy "$@"; return; fi
  # Persistent vulnerability DB cache between runs.
  local TOOL_EXTRA_ARGS=(-v "$(host_path "$TOOLS_STATE/trivy-cache"):/root/.cache/trivy")
  _tool_run "$TRIVY_IMAGE" "$@"
}
skopeo() {
  if type -P skopeo >/dev/null 2>&1; then command skopeo "$@"; return; fi
  # --mount instead of -v: the target path contains the registry port (a colon).
  local TOOL_EXTRA_ARGS=(-e REGISTRY_AUTH_FILE=/docker-config/config.json
    --mount "type=bind,src=$(host_path "$TOOLS_STATE/ca"),dst=/etc/containers/certs.d/$REGISTRY,readonly")
  _tool_run "$SKOPEO_IMAGE" "$@"
}
