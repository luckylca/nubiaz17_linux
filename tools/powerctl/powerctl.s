// powerctl — direct reboot(2) syscall, multi-call by argv[1].
//
// The Ubuntu rootfs has no systemd running (PID1 is /bin/sh /init), but
// /usr/sbin/{reboot,poweroff,halt,shutdown} are all symlinks to systemctl,
// which refuses to run without /run/systemd/system — so "关机没用".
// This static stub bypasses init entirely and calls the kernel directly.
//
//   powerctl poweroff    LINUX_REBOOT_CMD_POWER_OFF (0x4321fedc)
//   powerctl halt        same as poweroff (no userspace left to stop)
//   powerctl reboot      LINUX_REBOOT_CMD_RESTART   (0x01234567)
//   powerctl bootloader  LINUX_REBOOT_CMD_RESTART2  (0xa1b2c3d4, "bootloader")
//
// Unknown/missing argument -> prints usage to stderr and exits 1.
    .text
    .global _start
_start:
    ldr  x0, [sp]          // argc
    cmp  x0, #2
    b.lt usage
    ldr  x1, [sp, #16]     // argv[1] (sp: argc, argv[0], argv[1], ...)
    ldrb w2, [x1]
    cmp  w2, #'p'
    b.eq poweroff
    cmp  w2, #'h'
    b.eq poweroff
    cmp  w2, #'r'
    b.eq restart
    cmp  w2, #'b'
    b.eq bootloader
    b    usage

poweroff:
    movz x2, #0xfedc
    movk x2, #0x4321, lsl #16
    b    call

restart:
    movz x2, #0x4567
    movk x2, #0x0123, lsl #16
    b    call

bootloader:
    movz x2, #0xc3d4
    movk x2, #0xa1b2, lsl #16
    adr  x3, cmd_bl
    b    call2

call:
    mov  x3, xzr
call2:
    movz x0, #0xdead
    movk x0, #0xfee1, lsl #16
    movz x1, #0x1969
    movk x1, #0x2812, lsl #16
    movz x8, #142          // reboot(2)
    svc  #0
    // on success we never return; on failure fall through to exit(1)
    movz x0, #1
    movz x8, #93
    svc  #0

usage:
    movz x0, #2            // stderr
    adr  x1, msg
    adr  x3, msg_end
    sub  x2, x3, x1        // length
    movz x8, #64           // write(2)
    svc  #0
    movz x0, #1
    movz x8, #93           // exit(2)
    svc  #0

cmd_bl:
    .asciz "bootloader"
msg:
    .ascii "usage: powerctl poweroff|halt|reboot|bootloader\n"
msg_end:
