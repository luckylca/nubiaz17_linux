#!/bin/sh
# server-watch dashboard launcher — opens the kiosk browser on the X desktop.
# The agent stays running in the background; this only opens/closes the UI.
PATH=/bin:/sbin:/usr/bin:/usr/sbin

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/root/.Xauthority}"

URL="http://127.0.0.1:8765"
PROFILE=/tmp/server-watch-kiosk-profile
MARKER=server-watch-kiosk

# wait for the agent (max 15 s)
i=0
while [ $i -lt 30 ]; do
  if wget -q -O /dev/null "$URL/api/health" 2>/dev/null; then
    break
  fi
  i=$((i+1))
  sleep 0.5
done

pick_browser() {
  for b in chromium chromium-browser google-chrome google-chrome-stable microsoft-edge falkon firefox; do
    if command -v "$b" >/dev/null 2>&1; then
      echo "$b"
      return 0
    fi
  done
  return 1
}

B=$(pick_browser) || { echo "server-watch: no browser found" >&2; exit 1; }

# record our PID: after exec the browser inherits it, and the agent's
# /api/ui/quit endpoint uses this file to close the kiosk on double-tap.
echo $$ > /tmp/server-watch-kiosk.pid 2>/dev/null || true

case "$B" in
  chromium*|google-chrome*|microsoft-edge)
    exec "$B" \
      --app="$URL" \
      --user-data-dir="$PROFILE" \
      --class="$MARKER" \
      --kiosk \
      --no-sandbox --disable-dev-shm-usage \
      --no-first-run --no-default-browser-check \
      --disable-session-crashed-bubble --disable-infobars \
      --disable-features=TranslateUI \
      --autoplay-policy=no-user-gesture-required \
      --start-maximized
    ;;
  falkon)
    # falkon has no true kiosk; -k is kiosk mode
    exec "$B" -k "$URL"
    ;;
  firefox)
    exec "$B" --kiosk "$URL"
    ;;
esac
