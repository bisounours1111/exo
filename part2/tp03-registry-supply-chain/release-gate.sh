#!/usr/bin/env bash
# release-gate.sh IMAGE [--push REGISTRY_IMAGE]
# Refuses to publish an image that does not follow the Shop SAS policy.
#
# Checks on the local IMAGE (all of them run, the gate fails if one fails):
#   - OCI labels org.opencontainers.image.{version,revision,source} present
#   - non-root user
#   - HEALTHCHECK defined
#   - no fixable HIGH/CRITICAL vulnerability (trivy)
#   - no secret (trivy secret scanner)
# With --push, when every check passes: refuses `latest` and the rewrite of an existing semver tag,
# then pushes, signs the digest with cosign and attaches the SPDX SBOM as a signed attestation.
#
# Environment: COSIGN_KEY (default cosign.key), COSIGN_PASSWORD (default empty),
#              REGISTRY_USER / REGISTRY_PASSWORD (see tools.sh).
# Exit codes: 0 accepted, 1 refused, 2 usage, 3 publication error.
set -euo pipefail
cd "$(dirname "$0")"
# shellcheck source=tools.sh
. ./tools.sh

usage() { echo "usage: $0 IMAGE [--push REGISTRY_IMAGE]" >&2; exit 2; }
IMAGE="${1:-}"; [[ -n "$IMAGE" ]] || usage; shift
TARGET=""
while (( $# )); do
  case "$1" in
    --push) TARGET="${2:-}"; [[ -n "$TARGET" ]] || usage; shift 2 ;;
    *) usage ;;
  esac
done

COSIGN_KEY="${COSIGN_KEY:-cosign.key}"
export COSIGN_PASSWORD="${COSIGN_PASSWORD:-}"
SEMVER='^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'

failures=0
version_label=""
pass() { printf '[PASS] %s\n' "$*"; }
fail() { printf '[FAIL] %s\n' "$*"; failures=$((failures + 1)); }

if ! config="$(docker image inspect "$IMAGE" --format '{{json .Config}}' 2>/dev/null)"; then
  echo "[FAIL] image $IMAGE not found locally" >&2
  exit 1
fi
echo "== release gate: $IMAGE"

# Reports land in release/<image>/ for the CI artifacts.
REPORT_DIR="release/$(printf '%s' "$IMAGE" | tr '/:@' '___')"
mkdir -p "$REPORT_DIR"

# ---- OCI labels ----
for label in version revision source; do
  value="$(jq -r --arg k "org.opencontainers.image.$label" '.Labels[$k] // ""' <<<"$config")"
  if [[ -z "$value" || "$value" == "unknown" ]]; then
    fail "label org.opencontainers.image.$label missing"
  elif [[ "$label" == "version" && ! "$value" =~ $SEMVER ]]; then
    # Catches labels inherited from the base image (ubuntu sets version=22.04).
    fail "label org.opencontainers.image.version=$value is not semver"
  else
    pass "label org.opencontainers.image.$label=$value"
  fi
  [[ "$label" == "version" ]] && version_label="$value"
done

# ---- non-root user ----
user="$(jq -r '.User // ""' <<<"$config")"
case "${user%%:*}" in
  ""|root|0) fail "runs as root (USER='${user}')" ;;
  *) pass "user $user" ;;
esac

# ---- HEALTHCHECK ----
healthcheck="$(jq -r '.Healthcheck.Test // [] | join(" ")' <<<"$config")"
if [[ -z "$healthcheck" || "$healthcheck" == "NONE" ]]; then
  fail "no HEALTHCHECK"
else
  pass "healthcheck: $healthcheck"
fi

# ---- fixable HIGH/CRITICAL vulnerabilities ----
if trivy image --quiet --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --format json \
     "$IMAGE" > "$REPORT_DIR/vulnerabilities.json"; then
  vulns="$(jq -r '[.Results[]?.Vulnerabilities[]? | "\(.Severity) \(.VulnerabilityID) \(.PkgName) \(.InstalledVersion) -> \(.FixedVersion)"] | unique | .[]' \
    < "$REPORT_DIR/vulnerabilities.json")"
  if [[ -n "$vulns" ]]; then
    fail "$(wc -l <<<"$vulns" | tr -d ' ') fixable HIGH/CRITICAL vulnerabilities (report: $REPORT_DIR/vulnerabilities.json)"
    head -n 10 <<<"$vulns" | sed 's/^/         /'
  else
    pass "no fixable HIGH/CRITICAL vulnerability"
  fi
else
  fail "trivy vulnerability scan failed"
fi

# ---- secrets ----
if trivy image --quiet --scanners secret --format json "$IMAGE" > "$REPORT_DIR/secrets.json"; then
  secrets="$(jq -r '[.Results[]? | .Target as $t | .Secrets[]? | "\(.Severity) \(.RuleID) in \($t):\(.StartLine)"] | .[]' \
    < "$REPORT_DIR/secrets.json")"
  if [[ -n "$secrets" ]]; then
    fail "$(wc -l <<<"$secrets" | tr -d ' ') secret(s) found (report: $REPORT_DIR/secrets.json)"
    while read -r line; do printf '         %s\n' "$line"; done <<<"$secrets"
  else
    pass "no secret found"
  fi
else
  fail "trivy secret scan failed"
fi

# ---- target tag (only with --push) ----
if [[ -n "$TARGET" ]]; then
  repo="${TARGET%:*}"; tag="${TARGET##*:}"
  if [[ "$repo" == "$TARGET" || "$tag" == */* ]]; then
    fail "REGISTRY_IMAGE must include a tag: $TARGET"
  elif [[ "$tag" == "latest" ]]; then
    fail "tag latest is forbidden (see TAGGING.md)"
  elif [[ "$tag" =~ $SEMVER && "${tag#v}" != "${version_label#v}" ]]; then
    fail "tag $tag does not match label org.opencontainers.image.version=$version_label"
  elif [[ "$tag" =~ $SEMVER ]] && existing="$(crane digest "$TARGET" 2>/dev/null)"; then
    fail "$TARGET already exists ($existing): release tags are immutable, bump the version"
  else
    pass "target tag $TARGET"
  fi
fi

if (( failures )); then
  echo "== REFUSED: $failures check(s) failed"
  exit 1
fi
echo "== ACCEPTED"
[[ -n "$TARGET" ]] || exit 0

# ---- publication ----
publish_error() { echo "[ERROR] $*" >&2; exit 3; }
docker tag "$IMAGE" "$TARGET"
docker push -q "$TARGET" >/dev/null || publish_error "docker push $TARGET failed"
digest="$(crane digest "$TARGET")" || publish_error "cannot read the digest of $TARGET"
ref="$repo@$digest"
echo "[PUSH] $TARGET -> $digest"

cosign sign --yes --key "$COSIGN_KEY" --tlog-upload=false "$ref" >/dev/null 2>&1 \
  || publish_error "cosign sign failed"
cosign verify --key "${COSIGN_KEY%.key}.pub" --insecure-ignore-tlog=true "$ref" >/dev/null 2>&1 \
  || publish_error "signature verification failed"
echo "[SIGN] $ref"

syft "$ref" -o spdx-json > "$REPORT_DIR/sbom.spdx.json" 2>/dev/null || publish_error "syft failed"
cosign attest --yes --key "$COSIGN_KEY" --tlog-upload=false --type spdxjson \
  --predicate "$REPORT_DIR/sbom.spdx.json" "$ref" >/dev/null 2>&1 || publish_error "cosign attest failed"
echo "[SBOM] $(jq '.packages | length' < "$REPORT_DIR/sbom.spdx.json") packages attested on $ref"

# Line for the CI: the reference to deploy, pinned by digest.
echo "RELEASED=$TARGET@$digest"
