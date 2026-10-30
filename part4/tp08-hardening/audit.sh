#!/usr/bin/env bash
# audit.sh [NAME_REGEX]: security settings of the running containers (all, or those whose name matches).
# Exit code: 0 if no deviation, 1 otherwise.
#   ./audit.sh '^shop-'
set -euo pipefail
FILTER="${1:-.}"

containers=$(docker ps --format '{{.Names}}' | grep -E "$FILTER" | sort || true)
[ -n "$containers" ] || { echo "no running container matches '$FILTER'"; exit 1; }

deviations=0
printf '%-26s %-12s %-5s %-14s %-9s %-5s %-9s %-5s %-6s %s\n' \
  CONTAINER USER PRIV CAP_DROP CAP_ADD RO MEM PIDS NNP SOCKET
for c in $containers; do
  IFS='|' read -r user priv capdrop capadd ro mem pids secopt mounts < <(docker inspect "$c" --format \
    '{{.Config.User}}|{{.HostConfig.Privileged}}|{{join .HostConfig.CapDrop ","}}|{{join .HostConfig.CapAdd ","}}|{{.HostConfig.ReadonlyRootfs}}|{{.HostConfig.Memory}}|{{.HostConfig.PidsLimit}}|{{join .HostConfig.SecurityOpt ","}}|{{range .Mounts}}{{.Source}} {{end}}')
  [[ "$pids" =~ ^[0-9]+$ ]] || pids=0
  issues=()
  case "$user" in ""|root|0|0:*) issues+=("runs as root") ;; esac
  [ "$priv" = "true" ] && issues+=("privileged")
  [[ ",$capdrop," == *",ALL,"* ]] || issues+=("capabilities not dropped")
  [ "$ro" = "true" ] || issues+=("writable rootfs")
  [ "$mem" -gt 0 ] || issues+=("no memory limit")
  [ "$pids" -gt 0 ] || issues+=("no pids limit")
  [[ "$secopt" == *no-new-privileges* ]] || issues+=("no no-new-privileges")
  socket=no; [[ "$mounts" == *docker.sock* ]] && { socket=yes; issues+=("docker socket mounted"); }

  printf '%-26s %-12s %-5s %-14s %-9s %-5s %-9s %-5s %-6s %s\n' "$c" "${user:-root}" "$priv" "${capdrop:--}" \
    "${capadd:--}" "$ro" "$([ "$mem" -gt 0 ] && echo "$((mem / 1048576))M" || echo none)" \
    "$([ "$pids" -gt 0 ] && echo "$pids" || echo none)" \
    "$([[ "$secopt" == *no-new-privileges* ]] && echo yes || echo no)" "$socket"
  for i in "${issues[@]}"; do echo "    ! $i"; done
  deviations=$((deviations + ${#issues[@]}))
done

echo "deviations: $deviations"
[ "$deviations" -eq 0 ]
