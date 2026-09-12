// powerctl — direct reboot(2) syscall, exact-string dispatch.
//
// The Ubuntu rootfs has no systemd running (PID1 is /bin/sh /init), but
// /usr/sbin/{reboot,poweroff,halt,shutdown} are all symlinks to systemctl,
// which refuses to run without /run/systemd/system — so "关机没用".
// This static stub bypasses init entirely and calls the kernel directly.
//
//   powerctl poweroff    LINUX_REBOOT_CMD_POWER_OFF (0x4321fedc)
//   powerctl halt        LINUX_REBOOT_CMD_HALT      (0xcdef0123) — freezes
//                        the system without any PON power-off command, so
//                        the PMIC charger trigger does NOT auto-reboot us
//                        when USB is attached (2026-09-12: the real fix for
//                        "插线关机变重启"). Caller should blank fb0 first.
//   powerctl reboot      LINUX_REBOOT_CMD_RESTART   (0x01234567)
//   powerctl bootloader  LINUX_REBOOT_CMD_RESTART2  (0xa1b2c3d4, "bootloader")
//
// Argument must match one of the strings EXACTLY (2026-09-12: first-byte
// dispatch turned "bogus" into a fastboot reboot). Anything else prints
// usage to stderr and exits 1.
    .text
    .global _start
_start:
    ldr  x0, [sp]          // argc
    cmp  x0, #2
    b.lt usage
    ldr  x7, [sp, #16]     // x7 = argv[1]

    adr  x4, s_poweroff
    bl   match
    cbz  w5, poweroff
    adr  x4, s_halt
    bl   match
    cbz  w5, halt
    adr  x4, s_reboot
    bl   match
    cbz  w5, restart
    adr  x4, s_bootloader
    bl   match
    cbz  w5, bootloader
    b    usage

// match(x7=arg, x4=candidate) -> w5=0 iff strings equal (clobbers x5,x6,x8)
match:
    mov  x8, x7
1:  ldrb w5, [x8], #1
    ldrb w6, [x4], #1
    cmp  w5, w6
    b.ne 2f
    cbnz w5, 1b
2:  ret

poweroff:
    movz x2, #0xfedc
    movk x2, #0x4321, lsl #16
    b    call

halt:
    movz x2, #0x0123
    movk x2, #0xcdef, lsl #16
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

s_poweroff:
    .asciz "poweroff"
s_halt:
    .asciz "halt"
s_reboot:
    .asciz "reboot"
s_bootloader:
    .asciz "bootloader"
cmd_bl:
    .asciz "bootloader"
msg:
    .ascii "usage: powerctl poweroff|halt|reboot|bootloader\n"
msg_end:
