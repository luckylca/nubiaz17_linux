#!/sbin/sh
# NX563J / Android 15 / Magisk system-as-root compatibility for NetHunter's
# AnyKernel3 wrapper.
#
# Two issues need handling on this device:
#   1. The NetHunter anykernel.sh currently checks $splitimg while ak3-core.sh
#      defines $split_img. Alias it here so the Magisk ramdisk detected by
#      magiskboot is not misclassified as "no ramdisk".
#   2. A Magisk-patched SAR boot uses overlay.d for additional init *.rc files.
#      Root-level files copied directly into the Magisk ramdisk are not the
#      right persistence mechanism. Install the NetHunter rc through overlay.d
#      and place its HID report descriptors in overlay.d/sbin.

# Compatibility alias for the upstream anykernel.sh ramdisk-presence check.
splitimg="$split_img"

# Override the standard write_boot hook only for this device package. The
# caller has already run unpack_ramdisk(), so $ramdisk points at the extracted
# Magisk ramdisk and the usual ak3-core helpers remain available.
write_boot() {
  if [ -d "$ramdisk/overlay.d" ] && [ -f "$home/ramdisk-patch/init.nethunter.rc" ]; then
    ui_print "- NX563J: installing NetHunter init rc through Magisk overlay.d"
    mkdir -p "$ramdisk/overlay.d/sbin"

    # Magisk only guarantees newly-added auxiliary files below overlay.d/sbin.
    # ${MAGISKTMP} is expanded by magiskinit when the rc is injected.
    sed \
      -e 's#copy /keyboard-descriptor.bin#copy ${MAGISKTMP}/keyboard-descriptor.bin#' \
      -e 's#copy /mouse-descriptor.bin#copy ${MAGISKTMP}/mouse-descriptor.bin#' \
      "$home/ramdisk-patch/init.nethunter.rc" \
      > "$ramdisk/overlay.d/init.nethunter.rc"

    cp -f "$home/ramdisk-patch/keyboard-descriptor.bin" \
      "$ramdisk/overlay.d/sbin/keyboard-descriptor.bin"
    cp -f "$home/ramdisk-patch/mouse-descriptor.bin" \
      "$ramdisk/overlay.d/sbin/mouse-descriptor.bin"

    # Keep the generic helper available if the installer supplied it.
    if [ -f "$home/ramdisk-patch/sbin/usb_config.sh" ]; then
      cp -f "$home/ramdisk-patch/sbin/usb_config.sh" \
        "$ramdisk/overlay.d/sbin/usb_config.sh"
      chmod 0755 "$ramdisk/overlay.d/sbin/usb_config.sh"
    fi

    chmod 0750 "$ramdisk/overlay.d/init.nethunter.rc"
    chmod 0644 "$ramdisk/overlay.d/sbin/keyboard-descriptor.bin" \
      "$ramdisk/overlay.d/sbin/mouse-descriptor.bin"
  else
    # Fallback for a non-Magisk ramdisk. This keeps the device package usable
    # if the boot layout changes later while preserving the legacy NetHunter
    # root-ramdisk behaviour.
    ui_print "- NX563J: applying NetHunter files to conventional ramdisk"
    cp -rp "$home/ramdisk-patch/." "$ramdisk/"

    if [ -e "$ramdisk/init.rc" ] && ! grep -q '/init.nethunter.rc' "$ramdisk/init.rc"; then
      insert_after_last "$ramdisk/init.rc" 'import .*\.rc' 'import /init.nethunter.rc'
    fi
    if [ -e "$ramdisk/ueventd.rc" ] && ! grep -q '/dev/hidg\*' "$ramdisk/ueventd.rc"; then
      insert_after_last "$ramdisk/ueventd.rc" '/dev/kgsl.*root.*root' '# HID driver\n/dev/hidg* 0666 root root'
    fi
  fi

  repack_ramdisk
  flash_boot
  flash_dtbo
}
