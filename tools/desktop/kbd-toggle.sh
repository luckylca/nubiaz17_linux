#!/bin/sh
# kbd-toggle.sh — show/hide the matchbox on-screen keyboard (NX563J).
#
# Bound to the keyboard icon in the LXQt quicklaunch. matchbox-keyboard
# places itself partially OFF-SCREEN on this display (it assumes a
# portrait 1080x1920 panel; X runs 1920x1080), so after every start we
# pin it centered just above the 128px panel.
#
# Why matchbox and not onboard: onboard 1.4.1 segfaults in osk.so on
# XInput2 raw events from our uinput touch clone (every tap kills it).
# matchbox-keyboard only SENDS XTest events and never listens to XI2
# raw input, so it survives touch. Verified 2026-09-12 (types into
# qterminal: letters, space, enter).
export DISPLAY=:0
PATH=/bin:/sbin:/usr/bin:/usr/sbin

# Serialize invocations: without this, a quick double-tap on the panel icon
# passes the pidof check in both instances before either has exec'd
# matchbox-keyboard -> two keyboard windows (2026-09-12 user report).
exec 9>/tmp/kbd-toggle.lock
flock -x 9 2>/dev/null || {
  # flock(1) missing: fall through unguarded (better than breaking the key)
  :
}

if pidof matchbox-keyboard >/dev/null 2>&1; then
  pkill -f "matchbox-k[e]yboard"
  exit 0
fi

# 9>&- is essential: matchbox-keyboard must NOT inherit the lock fd, or it
# holds the flock for its whole lifetime and every later toggle blocks.
setsid matchbox-keyboard >/dev/null 2>&1 9>&- &
i=0
while [ $i -lt 20 ]; do
  wmctrl -l 2>/dev/null | grep -q " Keyboard$" && break
  i=$((i + 1))
  sleep 0.5
done
# x=420 centers the 1080-wide keyboard on the 1920-wide screen;
# y=520 puts its bottom edge (520+432=952) right above the panel.
wmctrl -r "Keyboard" -e 0,420,520,1080,432 2>/dev/null
