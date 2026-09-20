#!/bin/sh
# server-watch uninstaller — runs ON the phone. Does not touch user data,
# containers or the boot script beyond removing our own hook line.
set -e

pkill -f server-watch-agent-run 2>/dev/null || true
pkill -f "^/usr/local/bin/server-watch-agent$" 2>/dev/null || true
pkill -f server-watch-kiosk 2>/dev/null || true

for f in /root/rc.boot.ubuntu /root/initramfs/rc.boot.ubuntu; do
  if [ -f "$f" ] && grep -q "server-watch-agent-run" "$f"; then
    grep -v "server-watch" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    echo "unhooked: $f"
  fi
done

rm -f /usr/local/bin/server-watch-agent \
      /usr/local/bin/server-watch-agent-run \
      /usr/local/bin/server-watch-dashboard \
      /usr/local/bin/server-watch-webview \
      /usr/local/bin/server-watch-native \
      /usr/local/bin/server-watch-fb-kick \
      /usr/local/bin/server-watch-device-check \
      /root/.local/share/applications/server-watch.desktop \
      "/root/Desktop/Server Watch.desktop"
rm -rf /usr/local/share/server-watch
echo "removed. config kept at /etc/server-watch (delete manually if wanted)"
