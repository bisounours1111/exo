#!/usr/bin/env bash
# release-gate.sh IMAGE
# Objectif : refuser la publication d'une image qui ne respecte pas la politique Shop SAS.
# À compléter : SBOM, scan, signature, labels obligatoires, utilisateur non-root.
set -euo pipefail
IMAGE="${1:?usage: release-gate.sh IMAGE}"
echo "TODO: vérifier $IMAGE"
exit 1
