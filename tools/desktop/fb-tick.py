#!/usr/bin/env python3
# fb-tick.py — keep a command-mode DSI panel (mdss) refreshing from fb0.
#
# The JDI R63452 is a *command-mode* panel: the kernel only pushes pixels to
# the panel when someone issues FBIOPAN_DISPLAY (a "commit"). fbdash did that
# in its draw loop, but Xorg's fbdev driver just writes the mmap'd fb memory
# and never commits — so without this ticker the physical screen keeps
# showing whatever was last committed (e.g. a frozen fbdash frame) while X
# renders happily into memory.
#
# Run as a daemon whenever an X session owns the screen:
#   setsid python3 /root/fb-tick.py &
import array
import fcntl
import time

FBIOGET_VSCREENINFO = 0x4600
FBIOPAN_DISPLAY = 0x4606
FB_ACTIVATE_NOW = 0
FB_ACTIVATE_FORCE = 128

# struct fb_var_screeninfo is 160 bytes on 64-bit kernels.
# offsets: yoffset=20, activate=64
var = array.array('B', bytes(160))

fd = None
while True:
    try:
        if fd is None:
            fd = open('/dev/fb0', 'rb+', buffering=0)
        fcntl.ioctl(fd, FBIOGET_VSCREENINFO, var, True)
        struct_yoff = 20
        struct_act = 64
        var[struct_yoff:struct_yoff + 4] = (0).to_bytes(4, 'little')
        var[struct_act:struct_act + 4] = (FB_ACTIVATE_NOW | FB_ACTIVATE_FORCE).to_bytes(4, 'little')
        fcntl.ioctl(fd, FBIOPAN_DISPLAY, var, True)
        time.sleep(0.1)
    except Exception:
        # fb0 may briefly vanish during session switches; back off and retry
        if fd is not None:
            try:
                fd.close()
            except Exception:
                pass
            fd = None
        time.sleep(1)
