#!/usr/bin/env bash
# release-gate.sh IMAGE [--push REGISTRY_IMAGE]
# The release gate lives next to tools.sh, one level up.
exec "$(dirname "$0")/../release-gate.sh" "$@"
