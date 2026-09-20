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
[ -f server-watch-webview.py ] && install -m 0755 server-watch-webview.py "$PREFIX/bin/server-watch-webview"
# One-time migration cleanup for devices that ran the short-lived native-clock
# experiment. It is not installed or used anymore; Full Dashboard is the only UI.
pkill -TERM -f '^python3 /usr/local/bin/server-watch-native( |$)' 2>/dev/null || true
rm -f "$PREFIX/bin/server-watch-native" /tmp/server-watch-native.pid
[ -f server-watch-fb-kick.py ] && install -m 0755 server-watch-fb-kick.py "$PREFIX/bin/server-watch-fb-kick"
[ -f device-check.sh ] && install -m 0755 device-check.sh "$PREFIX/bin/server-watch-device-check"

echo "==> icon + desktop entry"
mkdir -p "$PREFIX/share/server-watch" /root/.local/share/applications /root/Desktop
install -m 0644 icon.png "$PREFIX/share/server-watch/icon.png"
install -m 0644 server-watch.desktop /root/.local/share/applications/server-watch.desktop
install -m 0755 server-watch.desktop "/root/Desktop/Server Watch.desktop"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database /root/.local/share/applications 2>/dev/null || true

# Put Server Watch in LXQt's quick-launch area so touch users can open it
# with ONE tap. Desktop-file activation may still require a double-click in
# PCManFM, which is unreliable with the NX563J touch translator.
PANEL=/root/.config/lxqt/panel.conf
if [ -f "$PANEL" ] && command -v python3 >/dev/null 2>&1; then
  PANEL_CHANGED="$(python3 - "$PANEL" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
lines = p.read_text().splitlines()
try:
    start = lines.index('[quicklaunch]')
except ValueError:
    print('unchanged'); raise SystemExit
end = next((i for i in range(start + 1, len(lines)) if lines[i].startswith('[')), len(lines))
block = lines[start + 1:end]
if any('server-watch.desktop' in line for line in block):
    print('unchanged'); raise SystemExit
size = 0
for line in block:
    if line.startswith('apps\\size='):
        try: size = int(line.split('=', 1)[1])
        except ValueError: pass
idx = size + 1
block = [line for line in block if not line.startswith('apps\\size=')]
block += [f'apps\\{idx}\\desktop=/root/.local/share/applications/server-watch.desktop', f'apps\\size={idx}']
lines[start + 1:end] = block
p.write_text('\n'.join(lines) + '\n')
print('changed')
PY
)"
  RESTART_PANEL=0
  [ "$PANEL_CHANGED" = changed ] && RESTART_PANEL=1
  if [ "$RESTART_PANEL" -eq 1 ] && pidof lxqt-panel >/dev/null 2>&1; then
    killall lxqt-panel 2>/dev/null || true
    sleep 0.5
  fi

  # This custom LXQt session does not always respawn lxqt-panel after a
  # kill. Re-launch it explicitly with the live session's D-Bus/X11
  # environment. This also repairs a panel that was already missing.
  if ! pidof lxqt-panel >/dev/null 2>&1 && command -v lxqt-panel >/dev/null 2>&1; then
    SESSION_PID="$(pidof lxqt-session 2>/dev/null | awk '{print $1}')"
    DISPLAY_ENV=:0
    XAUTH_ENV=/root/.Xauthority
    DBUS_ENV=""
    if [ -n "$SESSION_PID" ] && [ -r "/proc/$SESSION_PID/environ" ]; then
      DISPLAY_ENV="$(tr '\000' '\n' < "/proc/$SESSION_PID/environ" | sed -n 's/^DISPLAY=//p' | head -1)"
      XAUTH_ENV="$(tr '\000' '\n' < "/proc/$SESSION_PID/environ" | sed -n 's/^XAUTHORITY=//p' | head -1)"
      DBUS_ENV="$(tr '\000' '\n' < "/proc/$SESSION_PID/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | head -1)"
      [ -n "$DISPLAY_ENV" ] || DISPLAY_ENV=:0
      [ -n "$XAUTH_ENV" ] || XAUTH_ENV=/root/.Xauthority
    fi
    if [ -n "$DBUS_ENV" ]; then
      setsid env HOME=/root USER=root DISPLAY="$DISPLAY_ENV" XAUTHORITY="$XAUTH_ENV" DBUS_SESSION_BUS_ADDRESS="$DBUS_ENV" lxqt-panel >/tmp/lxqt-panel.log 2>&1 </dev/null &
    else
      setsid env HOME=/root USER=root DISPLAY="$DISPLAY_ENV" XAUTHORITY="$XAUTH_ENV" lxqt-panel >/tmp/lxqt-panel.log 2>&1 </dev/null &
    fi
    sleep 1
  fi
fi

echo "==> config"
mkdir -p "$ETC"
[ -f "$ETC/config.yaml" ] || cat > "$ETC/config.yaml" <<'YAML'
listen: 127.0.0.1:8765
sample_interval_ms: 2000
slow_interval_ms: 20000
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

# Upgrade only the old stock sampling defaults. Custom values are preserved.
if grep -q '^sample_interval_ms: 1000$' "$ETC/config.yaml" 2>/dev/null; then
  sed -i 's/^sample_interval_ms: 1000$/sample_interval_ms: 2000/' "$ETC/config.yaml"
fi
if grep -q '^slow_interval_ms: 10000$' "$ETC/config.yaml" 2>/dev/null; then
  sed -i 's/^slow_interval_ms: 10000$/slow_interval_ms: 20000/' "$ETC/config.yaml"
fi

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
pkill -f "^/usr/local/bin/server-watch-agent$" 2>/dev/null || true
sleep 1
setsid /usr/local/bin/server-watch-agent-run >/dev/null 2>&1 &
sleep 2
if wget -q -O /dev/null http://127.0.0.1:8765/api/health; then
  echo "OK: agent answering on http://127.0.0.1:8765"
else
  echo "WARN: agent not answering yet — check /var/log/server-watch-agent.log"
fi
