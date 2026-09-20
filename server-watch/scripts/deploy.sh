#!/usr/bin/env bash
# Build and deploy Server Watch to the NX563J Ubuntu phone.
# Optional: PHONE=<ip> KEY=<private-key> LAUNCH=1 ./scripts/deploy.sh
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
    # NX563J USB gadget address only. Do not reuse unrelated Tailscale peers.
    candidates=(10.42.0.1)
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
  echo "NX563J is not reachable over SSH. Connect USB networking, or pass PHONE=<verified NX563J IP> explicitly." >&2
  exit 2
}

echo "==> target: $PHONE"
"$ROOT/scripts/build.sh"

PKG="$(mktemp -d /tmp/server-watch-pkg.XXXXXX)"
trap 'rm -rf "$PKG"' EXIT
cp "$ROOT/dist/server-watch-agent-linux-arm64" "$PKG/server-watch-agent"
cp "$ROOT"/packaging/{server-watch-agent-run.sh,server-watch-dashboard.sh,server-watch-webview.py,server-watch-fb-kick.py,server-watch.desktop,icon.png,install.sh,uninstall.sh} "$PKG/"
cp "$ROOT/scripts/device-check.sh" "$PKG/device-check.sh"

echo "==> upload"
ssh "${SSH_OPTS[@]}" "root@$PHONE" 'rm -rf /tmp/server-watch-pkg && mkdir -p /tmp/server-watch-pkg'
scp "${SSH_OPTS[@]}" "$PKG"/* "root@$PHONE:/tmp/server-watch-pkg/"

echo "==> install"
ssh "${SSH_OPTS[@]}" "root@$PHONE" 'cd /tmp/server-watch-pkg && sh install.sh'

if [[ "${LAUNCH:-0}" == "1" ]]; then
  echo "==> restart dashboard for performance validation"
  ssh "${SSH_OPTS[@]}" "root@$PHONE" '
    # Clean up the single full-dashboard frontend before relaunching it.
    for pat in "^python3 /usr/local/bin/server-watch-webview( |$)"; do
      pgrep -f "$pat" 2>/dev/null | while read p; do
        [ -n "$p" ] && kill -TERM "$p" 2>/dev/null || true
      done
    done
    sleep 1
    for pat in "^python3 /usr/local/bin/server-watch-webview( |$)"; do
      pgrep -f "$pat" 2>/dev/null | while read p; do
        [ -n "$p" ] && kill -KILL "$p" 2>/dev/null || true
      done
    done
    sleep 0.5
    rm -f /tmp/server-watch-kiosk.pid
    rm -rf /tmp/server-watch-dashboard.lock
    setsid /usr/local/bin/server-watch-dashboard >/tmp/server-watch-dashboard.log 2>&1 </dev/null &
  '
  sleep 5
fi

echo "==> device validation"
ssh "${SSH_OPTS[@]}" "root@$PHONE" '/usr/local/bin/server-watch-device-check' || true

if [[ "${INTERACTION_TEST:-0}" == "1" ]]; then
  echo "==> interaction lifecycle test"
  ssh "${SSH_OPTS[@]}" "root@$PHONE" '
    set -eu
    old=$(cat /tmp/server-watch-kiosk.pid 2>/dev/null || true)
    [ -n "$old" ] || { echo "FAIL: no kiosk pid before exit test"; exit 1; }
    echo "    running_pid=$old"
    wget -qO- --post-data='' http://127.0.0.1:8765/api/ui/quit >/dev/null 2>&1 || { echo "FAIL: /api/ui/quit request failed"; exit 1; }
    i=0
    while kill -0 "$old" 2>/dev/null && [ $i -lt 30 ]; do i=$((i+1)); sleep 0.1; done
    if kill -0 "$old" 2>/dev/null; then echo "FAIL: UI did not exit"; exit 1; fi
    i=0
    while { [ -e /tmp/server-watch-kiosk.pid ] || [ -d /tmp/server-watch-dashboard.lock ]; } && [ $i -lt 30 ]; do
      i=$((i+1)); sleep 0.1
    done
    [ ! -e /tmp/server-watch-kiosk.pid ] || { echo "FAIL: kiosk pidfile not cleaned"; exit 1; }
    [ ! -d /tmp/server-watch-dashboard.lock ] || { echo "FAIL: launcher lock not cleaned"; exit 1; }
    if grep -q "kick OK" /tmp/server-watch-fb-kick.log 2>/dev/null; then
      echo "    desktop_fb_kick=OK"
    else
      echo "FAIL: framebuffer restore kick missing"; cat /tmp/server-watch-fb-kick.log 2>/dev/null || true; exit 1
    fi
    setsid /usr/local/bin/server-watch-dashboard >/tmp/server-watch-dashboard.log 2>&1 </dev/null &
    i=0
    while [ ! -s /tmp/server-watch-kiosk.pid ] && [ $i -lt 30 ]; do i=$((i+1)); sleep 0.1; done
    new=$(cat /tmp/server-watch-kiosk.pid 2>/dev/null || true)
    [ -n "$new" ] && kill -0 "$new" 2>/dev/null || { echo "FAIL: dashboard did not reopen"; exit 1; }
    [ "$new" != "$old" ] || { echo "FAIL: reopen reused stale pid"; exit 1; }
    echo "    reopened_pid=$new"
    echo "    lifecycle=PASS"
  '
fi

echo "==> installed. Launch from the LXQt menu: Server Watch"
