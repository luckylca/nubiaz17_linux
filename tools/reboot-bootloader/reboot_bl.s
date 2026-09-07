// reboot(LINUX_REBOOT_MAGIC1, MAGIC2, LINUX_REBOOT_CMD_RESTART2, "bootloader")
    .text
    .global _start
_start:
    movz x0, #0xdead
    movk x0, #0xfee1, lsl #16
    movz x1, #0x1969
    movk x1, #0x2812, lsl #16
    movz x2, #0xc3d4
    movk x2, #0xa1b2, lsl #16
    adr  x3, cmd
    movz x8, #142
    svc  #0
    movz x8, #93
    svc  #0
cmd:
    .asciz "bootloader"
