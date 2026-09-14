#!/bin/sh
# hid-gadget.sh — add HID keyboard + mouse functions to the running
# configfs gadget on NX563J (Phase 4, NetHunter HID-4).
#
# The kernel (4.4.302 downstream, v6) already has USB_CONFIGFS_F_HID=y,
# so this is pure userspace: create hid.usb0 (keyboard) and hid.usb1
# (mouse), link them into configs/c.1 alongside acm.GS0/ecm/ncm, and
# re-bind the UDC.
#
# WARNING: re-binding the UDC drops usb0 (ssh) for a second. Run with
# nohup/setsid so the script finishes even if the ssh session dies, and
# keep Wi-Fi ssh (192.168.1.186) as the fallback management channel.
#
# Result: /dev/hidg0 (keyboard, 8-byte boot reports) and
#         /dev/hidg1 (mouse, 3-byte reports: buttons, dx, dy).
#
# Usage:  sh hid-gadget.sh          # add HID functions (idempotent)
#         sh hid-gadget.sh remove   # back to acm+ecm+ncm only
set -u
G=/config/usb_gadget/nx563j
C=$G/configs/c.1

mountpoint -q /config 2>/dev/null || { mkdir -p /config; mount -t configfs none /config || { echo "FAIL: configfs"; exit 1; }; }
[ -d "$G" ] || { echo "FAIL: gadget $G missing"; exit 1; }

# Standard boot-protocol keyboard report descriptor (63 bytes, 8-byte report)
KBD_DESC='05010906a101050719e029e71500250175019508810295017508810195057501050819012905910295017503910195067508150025650507190029658100c0'
# Canonical 3-button mouse (46 bytes, 3-byte reports: buttons, dx, dy).
# This exact descriptor is the one that WORKS on macOS (2026-09-14):
#  - 4-byte wheel variant: enumerated as a mouse but pointer never moved
#  - report_length shorter than the descriptor's report: silently dropped
#  - subclass=1/protocol=2 (boot): ambiguous report length under boot
#    protocol, pointer dead. subclass=0/protocol=0 + this desc: pointer moves.
MOUSE_DESC='05010902a1010901a000050919012903150025019503750181029501750581010501093009311581257f750895028106c0c0'

if [ "${1:-}" = "remove" ]; then
  echo "" > $G/UDC 2>/dev/null
  rm -f $C/hid.usb0 $C/hid.usb1 2>/dev/null
  rmdir $G/functions/hid.usb0 $G/functions/hid.usb1 2>/dev/null
  echo a800000.dwc3 > $G/UDC
  echo "HID functions removed, gadget re-bound"
  exit 0
fi

# idempotent: already present?
if [ -d $G/functions/hid.usb0 ] && [ -L $C/hid.usb0 ] && [ -e /dev/hidg0 ]; then
  echo "HID already active: $(ls /dev/hidg* 2>/dev/null | tr '\n' ' ')"
  exit 0
fi

echo "== creating HID functions"
mkdir -p $G/functions/hid.usb0
echo 1      > $G/functions/hid.usb0/protocol   # keyboard
echo 1      > $G/functions/hid.usb0/subclass   # boot interface
echo 8      > $G/functions/hid.usb0/report_length
python3 -c "import os;os.write(1,bytes.fromhex('$KBD_DESC'))" > $G/functions/hid.usb0/report_desc

mkdir -p $G/functions/hid.usb1
echo 0      > $G/functions/hid.usb1/protocol   # report protocol only (boot mode broke macOS, see MOUSE_DESC)
echo 0      > $G/functions/hid.usb1/subclass
echo 3      > $G/functions/hid.usb1/report_length
python3 -c "import os;os.write(1,bytes.fromhex('$MOUSE_DESC'))" > $G/functions/hid.usb1/report_desc

echo "== re-binding gadget with HID (usb0 will flap!)"
echo "" > $G/UDC
sleep 1
ln -sf $G/functions/hid.usb0 $C/hid.usb0
ln -sf $G/functions/hid.usb1 $C/hid.usb1
echo a800000.dwc3 > $G/UDC
sleep 2

echo "== result"
ls -l /dev/hidg* 2>&1
cat /sys/class/usbmisc/hidg0/dev 2>/dev/null && echo " (hidg0 keyboard)"
cat /sys/class/usbmisc/hidg1/dev 2>/dev/null && echo " (hidg1 mouse)"
