#!/bin/sh
# server-watch dashboard launcher — opens the kiosk browser on the X desktop.
# The agent stays running in the background; this only opens/closes the UI.
PATH=/bin:/sbin:/usr/bin:/usr/sbin

export DISPLAY="${DISPLAY:-:0}"
export XAUTHORITY="${XAUTHORITY:-/root/.Xauthority}"

URL="http://127.0.0.1:8765"
PROFILE=/tmp/server-watch-kiosk-profile
MARKER=server-watch-kiosk
LOCKDIR=/tmp/server-watch-dashboard.lock

# Desktop touch can generate two launcher activations very close together.
# Keep exactly one dashboard instance, but recover from a stale lock left by
# a crash or power loss.
if ! mkdir "$LOCKDIR" 2>/dev/null; then
  old="$(cat "$LOCKDIR/pid" 2>/dev/null || true)"
  if [ -n "$old" ] && kill -0 "$old" 2>/dev/null; then
    exit 0
  fi
  rm -rf "$LOCKDIR"
  mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ > "$LOCKDIR/pid"
cleanup_lock() { rm -rf "$LOCKDIR"; }
trap cleanup_lock EXIT

restore_desktop() {
  rm -f /tmp/server-watch-kiosk.pid 2>/dev/null || true
  # Give Openbox/PCManFM a moment to repaint the newly exposed desktop in
  # Xorg's fbdev buffer, then issue exactly ONE panel commit. Never loop it:
  # repeated FBIOPAN_DISPLAY calls are known to wedge this downstream mdss.
  sleep 0.15
  if command -v xrefresh >/dev/null 2>&1; then
    xrefresh -root >/dev/null 2>&1 || true
  fi
  if [ -x /usr/local/bin/server-watch-fb-kick ]; then
    /usr/local/bin/server-watch-fb-kick >/tmp/server-watch-fb-kick.log 2>&1 || true
  fi
}

run_ui() {
  "$@"
  rc=$?
  restore_desktop
  return $rc
}

# wait for the agent (max 15 s)
i=0
while [ $i -lt 30 ]; do
  if wget -q -O /dev/null "$URL/api/health" 2>/dev/null; then
    break
  fi
  i=$((i+1))
  sleep 0.5
done

# The normal UI is always the full Vue dashboard in a minimal WebKitGTK shell.
# Keep a single frontend path: no intermediate/native clock screen.
export WEBKIT_DISABLE_COMPOSITING_MODE=1
export WEBKIT_DISABLE_DMABUF_RENDERER=1
export LIBGL_ALWAYS_SOFTWARE=1
if [ -x /usr/local/bin/server-watch-webview ] && python3 -c 'import gi; gi.require_version("WebKit2","4.1"); from gi.repository import WebKit2' 2>/dev/null; then
  run_ui /usr/local/bin/server-watch-webview
  exit $?
fi

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
    run_ui "$B" \
      --app="$URL" \
      --user-data-dir="$PROFILE" \
      --class="$MARKER" \
      --kiosk \
      --no-sandbox --disable-dev-shm-usage --disable-gpu \
      --disable-smooth-scrolling --disable-background-networking \
      --no-first-run --no-default-browser-check \
      --disable-session-crashed-bubble --disable-infobars \
      --disable-features=TranslateUI \
      --autoplay-policy=no-user-gesture-required \
      --start-maximized
    ;;
  falkon)
    run_ui "$B" -k "$URL"
    ;;
  firefox)
    run_ui "$B" --kiosk "$URL"
    ;;
esac
