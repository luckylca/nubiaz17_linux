#!/usr/bin/env python3
# fb-kick.py — ONE-SHOT FBIOPAN_DISPLAY for the JDI R63452 cmd-mode panel.
#
# mdss hardware autorefresh (msm_cmd_autorefresh_en, armed in rc.boot.ubuntu)
# only activates "in commit context when the next update is kicked off" — i.e.
# the panel keeps showing the last committed frame (the dead fbdash image)
# until exactly ONE pan lands. Xorg's fbdev driver never commits on its own.
#
# This issues that single kick and exits. Do NOT loop this: a 10 Hz ticker
# deadlocks the mdss dsi_event thread while Xorg runs (twice observed;
# D-state, screen frozen, only a reboot clears). One pan per X session is
# enough — after it, MDP hardware re-commits fb0 every frame with zero CPU.
#
# struct fb_var_screeninfo offsets on this arm64 kernel (160-byte struct):
#   yoffset  @ 20   (u32)
#   activate @ 84   (u32)   <-- NOT 64; an earlier draft had this wrong
import array
import fcntl
import sys

FBIOGET_VSCREENINFO = 0x4600
FBIOPAN_DISPLAY = 0x4606
FB_ACTIVATE_NOW = 0
FB_ACTIVATE_FORCE = 128

var = array.array('B', bytes(160))
fd = open('/dev/fb0', 'rb+', buffering=0)
fcntl.ioctl(fd, FBIOGET_VSCREENINFO, var, True)
var[20:24] = array.array('B', (0).to_bytes(4, 'little'))
var[84:88] = array.array('B', (FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE).to_bytes(4, 'little'))
fcntl.ioctl(fd, FBIOPAN_DISPLAY, var, True)
fd.close()
print("kick OK")
sys.exit(0)
