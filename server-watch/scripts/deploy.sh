#!/usr/bin/env bash
# Build and deploy Server Watch to the NX563J Ubuntu phone.
# Optional: PHONE=<ip> KEY=<private-key> ./scripts/deploy.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KEY="${KEY:-$ROOT/../work/nx563j_key}"

[[ -f "$KEY" ]] || { echo "missing SSH key: $KEY" >&2; exit 1; }

SSH_OPTS=(-i "$KEY" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new)

pick_phone() {
  local candidates=()
  if [[ -n "${PHONE:-}" ]]; then
    candidates=("$PHONE")
  else
    # USB gadget first, then the previously used Tailscale address.
    candidates=(10.42.0.1 100.72.56.85)
  fi
  local h
  for h in "${candidates[@]}"; do
    echo "==> probe root@$h" >&2
    if ssh "${SSH_OPTS[@]}" "root@$h" 'echo ok' >/dev/null 2>&1; then
      echo "$h"
      return 0
    fi
  done
  return 1
}

PHONE="$(pick_phone)" || {
  echo "NX563J is not reachable over SSH. Connect USB networking or Wi-Fi/Tailscale and retry." >&2
  exit 2
}

echo "==> target: $PHONE"
"$ROOT/scripts/build.sh"

PKG="$(mktemp -d /tmp/server-watch-pkg.XXXXXX)"
trap 'rm -rf "$PKG"' EXIT
cp "$ROOT/dist/server-watch-agent-linux-arm64" "$PKG/server-watch-agent"
cp "$ROOT"/packaging/{server-watch-agent-run.sh,server-watch-dashboard.sh,server-watch.desktop,icon.png,install.sh,uninstall.sh} "$PKG/"
cp "$ROOT/scripts/device-check.sh" "$PKG/device-check.sh"

echo "==> upload"
ssh "${SSH_OPTS[@]}" "root@$PHONE" 'rm -rf /tmp/server-watch-pkg && mkdir -p /tmp/server-watch-pkg'
scp "${SSH_OPTS[@]}" "$PKG"/* "root@$PHONE:/tmp/server-watch-pkg/"

echo "==> install"
ssh "${SSH_OPTS[@]}" "root@$PHONE" 'cd /tmp/server-watch-pkg && sh install.sh'

echo "==> device validation"
ssh "${SSH_OPTS[@]}" "root@$PHONE" '/usr/local/bin/server-watch-device-check' || true

echo "==> installed. Launch from the LXQt menu: Server Watch"
