#!/usr/bin/env bash
# retention.sh REPOSITORY [KEEP] [--apply]
# Keeps the KEEP most recent non-semver tags of REPOSITORY (default 5) and deletes the others.
# Semver tags (1.4.2, v2.0.0-rc.1), release aliases (1, 1.4) and cosign artifacts are never touched. Dry run unless --apply is given.
# Uses only the registry HTTP API (curl + jq). Tags are deleted one by one
# (DELETE /v2/<repo>/manifests/<tag>, distribution v3): a manifest shared with a kept tag survives.
# Space is reclaimed afterwards by the registry garbage-collect.
set -euo pipefail
# shellcheck source=tools.sh
. "$(dirname "$0")/tools.sh"

usage() { echo "usage: $0 REPOSITORY [KEEP] [--apply]" >&2; exit 2; }
REPO="${1:-}"; [[ -n "$REPO" ]] || usage; shift
KEEP=5; APPLY=0
for arg in "$@"; do
  case "$arg" in
    --apply) APPLY=1 ;;
    ''|*[!0-9]*) usage ;;
    *) KEEP="$arg" ;;
  esac
done

API="https://$REGISTRY/v2/$REPO"
ACCEPT="application/vnd.oci.image.index.v1+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.docker.distribution.manifest.v2+json"
SEMVER='^v?[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'
# Floating release aliases (1, 1.4) follow the semver releases and are kept as well.
RELEASE_ALIAS='^v?[0-9]+(\.[0-9]+)?$'
# cosign signatures, attestations and SBOMs are stored as sha256-<digest>.sig/.att/.sbom tags.
COSIGN_ARTIFACT='^sha256-[0-9a-f]{64}\.(sig|att|sbom)$'

# Creation date of a tag, read from the image config (first real platform for an index).
created_at() {
  local manifest digest config
  manifest="$(curl_reg -H "Accept: $ACCEPT" "$API/manifests/$1")"
  if [[ "$(jq -r '.manifests != null' <<<"$manifest")" == "true" ]]; then
    digest="$(jq -r '[.manifests[] | select(.platform.os != "unknown")][0].digest' <<<"$manifest")"
    manifest="$(curl_reg -H "Accept: $ACCEPT" "$API/manifests/$digest")"
  fi
  config="$(jq -r '.config.digest' <<<"$manifest")"
  curl_reg -L "$API/blobs/$config" | jq -r '.created // "1970-01-01T00:00:00Z"'
}

tags="$(curl_reg "$API/tags/list" | jq -r '.tags // [] | .[]')"
[[ -n "$tags" ]] || { echo "$REPO: no tags"; exit 0; }

candidates=()
while read -r tag; do
  if [[ "$tag" =~ $SEMVER ]]; then
    echo "keep    $tag (semver)"
  elif [[ "$tag" =~ $RELEASE_ALIAS ]]; then
    echo "keep    $tag (release alias)"
  elif [[ "$tag" =~ $COSIGN_ARTIFACT ]]; then
    echo "keep    $tag (cosign artifact)"
  else
    candidates+=("$(created_at "$tag") $tag")
  fi
done <<<"$tags"

# ISO 8601 dates sort lexically: most recent first.
rank=0
while read -r created tag; do
  [[ -n "$tag" ]] || continue
  rank=$((rank + 1))
  if (( rank <= KEEP )); then
    echo "keep    $tag ($created)"
  elif (( APPLY )); then
    code="$(curl_reg -o "$DEVNULL" -w '%{http_code}' -X DELETE "$API/manifests/$tag")" || code="curl error $?"
    [[ "$code" == "202" ]] || { echo "error   $tag: HTTP $code" >&2; exit 1; }
    echo "deleted $tag ($created)"
  else
    echo "delete  $tag ($created) [dry run]"
  fi
done < <(printf '%s\n' "${candidates[@]}" | sort -r)

if (( APPLY )); then
  echo "Run the garbage-collect to free the blobs:"
  echo "  docker compose -f starter/registry/compose.yml exec registry registry garbage-collect --delete-untagged /etc/distribution/config.yml"
fi
