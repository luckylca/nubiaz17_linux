#!/bin/sh
# onboard-setup.sh — onboard on-screen keyboard for the NX563J tablet session.
#
# Runs inside the session (autostart, session D-Bus up). Fixes the
# "keyboard vanishes on the first tap" bug: without these, onboard starts
# minimized and treats a tap as a focus change that re-hides it. We pin it
# docked at the bottom edge, never auto-hidden, always on top, finger-sized
# keys — then start onboard itself.
PATH=/bin:/sbin:/usr/bin:/usr/sbin

gsettings set org.onboard start-minimized false 2>/dev/null
gsettings set org.onboard.window force-to-top true 2>/dev/null
gsettings set org.onboard.window docking-enabled true 2>/dev/null
gsettings set org.onboard.window docking-edge 'bottom' 2>/dev/null
gsettings set org.onboard.window docking-shrink-workarea false 2>/dev/null
gsettings set org.onboard.auto-show enabled false 2>/dev/null
gsettings set org.onboard.auto-show hide-on-key-press false 2>/dev/null

exec onboard
