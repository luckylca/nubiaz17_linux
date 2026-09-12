#!/bin/sh
# desktop-stop.sh — leave the X desktop and go back to the fbdash dashboard.
# Killing mate-session ends the session cleanly; desktop.sh then relaunches
# fbdash with NOAUTOLAUNCH, so the screen shows the dashboard and waits.
PATH=/bin:/sbin:/usr/bin:/usr/sbin
pkill -f mate-session 2>/dev/null
pkill -f lxsession 2>/dev/null
# current desktop is LXQt: "lxqt-session" matches neither pattern above
pkill -f lxqt-session 2>/dev/null
# if the session is wedged, falling back to killing Xorg still works:
# desktop.sh's startx returns and fbdash comes up either way
