#!/usr/bin/env python3
# ONE-SHOT FBIOPAN_DISPLAY for the NX563J JDI R63452 command-mode panel.
# Never loop this: repeated pans can deadlock the downstream mdss driver.
import array
import fcntl

FBIOGET_VSCREENINFO = 0x4600
FBIOPAN_DISPLAY = 0x4606
FB_ACTIVATE_NOW = 0
FB_ACTIVATE_FORCE = 128

var = array.array('B', bytes(160))
with open('/dev/fb0', 'rb+', buffering=0) as fd:
    fcntl.ioctl(fd, FBIOGET_VSCREENINFO, var, True)
    var[20:24] = array.array('B', (0).to_bytes(4, 'little'))
    var[84:88] = array.array('B', (FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE).to_bytes(4, 'little'))
    fcntl.ioctl(fd, FBIOPAN_DISPLAY, var, True)
print("kick OK")
