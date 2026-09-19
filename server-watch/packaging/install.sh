#!/bin/sh
# server-watch installer — runs ON the Ubuntu phone (as root).
# No systemd on this rootfs: the agent is supervised by a respawn loop
# started from rc.boot.ubuntu, exactly like dockerd.
set -e

PREFIX=/usr/local
ETC=/etc/server-watch
RC=/etc/rc.boot.ubuntu   # symlink/copy of the live boot script, see below

echo "==> install binary"
install -m 0755 server-watch-agent "$PREFIX/bin/server-watch-agent"
install -m 0755 server-watch-agent-run.sh "$PREFIX/bin/server-watch-agent-run"
install -m 0755 server-watch-dashboard.sh "$PREFIX/bin/server-watch-dashboard"
[ -f device-check.sh ] && install -m 0755 device-check.sh "$PREFIX/bin/server-watch-device-check"

echo "==> icon + desktop entry"
mkdir -p "$PREFIX/share/server-watch" /root/.local/share/applications /root/Desktop
install -m 0644 icon.png "$PREFIX/share/server-watch/icon.png"
install -m 0644 server-watch.desktop /root/.local/share/applications/server-watch.desktop
install -m 0755 server-watch.desktop "/root/Desktop/Server Watch.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /root/.local/share/applications 2>/dev/null || true

echo "==> config"
mkdir -p "$ETC"
[ -f "$ETC/config.yaml" ] || cat > "$ETC/config.yaml" <<'YAML'
listen: 127.0.0.1:8765
sample_interval_ms: 1000
slow_interval_ms: 10000
temp_warning: 65
temp_critical: 78
batt_temp_warning: 43
storage_warning: 85
memory_warning: 90
night_mode: true
dim_timeout_sec: 120
burnin_protection: true
docker_enable: true
bluetooth_enable: true
net_interface: ""
YAML

echo "==> hook into boot"
# rc.boot.ubuntu lives in the git checkout of the boot scripts on the
# device at /root/rc.boot.ubuntu (invoked by the initramfs). Add one
# idempotent line that starts the supervised agent.
for f in /root/rc.boot.ubuntu /root/initramfs/rc.boot.ubuntu; do
  if [ -f "$f" ]; then
    if ! grep -q "server-watch-agent-run" "$f"; then
      printf '\n# server-watch: desktop clock + monitor agent (supervised respawn)\n[ -x /usr/local/bin/server-watch-agent-run ] && setsid /usr/local/bin/server-watch-agent-run >/dev/null 2>&1 &\n' >> "$f"
      echo "    hooked: $f"
    else
      echo "    already hooked: $f"
    fi
  fi
done

echo "==> (re)start agent now"
pkill -f server-watch-agent-run 2>/dev/null || true
pkill -x server-watch-agent 2>/dev/null || true
sleep 1
setsid /usr/local/bin/server-watch-agent-run >/dev/null 2>&1 &
sleep 2
if wget -q -O /dev/null http://127.0.0.1:8765/api/health; then
  echo "OK: agent answering on http://127.0.0.1:8765"
else
  echo "WARN: agent not answering yet — check /var/log/server-watch-agent.log"
fi
