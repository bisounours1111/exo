#!/usr/bin/env bash
# verified-run.sh [docker run options...] IMAGE [command...]
# Bonus B3: runs `docker run` only if IMAGE carries a valid cosign signature made with cosign.pub.
# The image is resolved to its digest first and started by digest, so the tag cannot move
# between the verification and the run.
#   ./verified-run.sh --rm -p 3000:3000 localhost:5000/release/shopapi:1.4.2
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# tools.sh mounts $PWD into the tool containers: run them from the script directory.
pushd "$SCRIPT_DIR" >/dev/null
# shellcheck source=tools.sh
. ./tools.sh
popd >/dev/null
COSIGN_PUB="${COSIGN_PUB:-cosign.pub}"

# The image is the first argument that is neither an option nor an option value.
args=("$@"); image_index=-1; i=0
while (( i < ${#args[@]} )); do
  case "${args[i]}" in
    --rm|-d|--detach|-i|-t|-it|--init|--read-only|--privileged) ;;
    --*=*) ;;
    -*) i=$((i + 1)) ;;
    *) image_index=$i; break ;;
  esac
  i=$((i + 1))
done
(( image_index >= 0 )) || { echo "usage: $0 [docker run options...] IMAGE [command...]" >&2; exit 2; }
image="${args[image_index]}"

pushd "$SCRIPT_DIR" >/dev/null
if ! digest="$(crane digest "$image" 2>/dev/null)"; then
  echo "[verified-run] $image: not found in a registry, refused" >&2; exit 1
fi
repo="${image%@*}"; [[ "${repo##*/}" == *:* ]] && repo="${repo%:*}"
if ! cosign verify --key "$COSIGN_PUB" --insecure-ignore-tlog=true "$repo@$digest" >/dev/null 2>&1; then
  echo "[verified-run] $image ($digest): no valid signature, refused" >&2; exit 1
fi
popd >/dev/null

echo "[verified-run] $image: signature OK, running $repo@$digest" >&2
args[image_index]="$repo@$digest"
exec docker run "${args[@]}"
