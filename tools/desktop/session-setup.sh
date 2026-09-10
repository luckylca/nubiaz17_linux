#!/bin/sh
# session-setup.sh — one-shot MATE session tuning for the NX563J tablet.
#
# Runs from ~/.config/autostart inside the session (D-Bus up). Applies the
# touch-tablet settings that can't live in static files: 2x font scaling
# (mate-settings-daemon would otherwise clamp Xft.dpi to its own value),
# Ubuntu-MATE theme, finger-sized panels, bottom-docked onboard defaults.
# Idempotent: gsettings writes the same values every login, cheap.
PATH=/bin:/sbin:/usr/bin:/usr/sbin

# 2x scaling. mate-settings-daemon OWNS Xft.dpi once the session runs and
# overwrites the xrdb value with org.mate.font-rendering dpi (default 96),
# so set it there, not only in ~/.Xdefaults.
gsettings set org.mate.font-rendering dpi 192.0 2>/dev/null

# Ubuntu look (installed by yaru-theme-gtk / ubuntu-mate-artwork)
gsettings set org.mate.interface gtk-theme 'Yaru' 2>/dev/null
gsettings set org.mate.interface icon-theme 'Yaru' 2>/dev/null
gsettings set org.mate.Marco.general theme 'Yaru' 2>/dev/null
gsettings set org.mate.interface font-name 'Ubuntu 13' 2>/dev/null
gsettings set org.mate.interface document-font-name 'Ubuntu 13' 2>/dev/null
gsettings set org.mate.interface monospace-font-name 'Ubuntu Mono 14' 2>/dev/null
gsettings set org.mate.Marco.general titlebar-font 'Ubuntu Bold 13' 2>/dev/null

# finger-sized panels: default 24px bars are untappable at 400 dpi
for p in $(gsettings get org.mate.panel toplevel-id-list 2>/dev/null | tr -d "[],'"); do
  gsettings set "org.mate.panel.toplevel:/org/mate/panel/toplevels/$p/" size 64 2>/dev/null
done

# on-screen keyboard: docked at bottom, never minimized, always on top —
# the default "start minimized + hide on focus change" is what made it
# vanish on the first tap in the LXDE session
gsettings set org.onboard start-minimized false 2>/dev/null
gsettings set org.onboard.window force-to-top true 2>/dev/null
gsettings set org.onboard.window docking-enabled true 2>/dev/null
gsettings set org.onboard.window docking-edge 'bottom' 2>/dev/null
gsettings set org.onboard.auto-show enabled false 2>/dev/null
gsettings set org.onboard.auto-show hide-on-key-press false 2>/dev/null
