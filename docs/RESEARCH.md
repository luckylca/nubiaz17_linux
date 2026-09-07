# Research notes

## Downstream baseline

Current LineageOS NX563J uses:

- kernel source: `LineageOS/android_kernel_nubia_msm8998`
- kernel version: 4.4.302
- defconfig: `lineageos_nx563j_defconfig`
- image: `Image.gz-dtb`
- bootloader board: `msm8998`
- boot base: `0x00000000`
- pagesize: `4096`
- boot partition: `67108864` bytes
- UFS boot path: `soc/1da4000.ufshc`

Current LineageOS fstab names include `boot`, `recovery`, `modem`, `bluetooth`, `dsp`, `persist`, `cache`, `userdata` and `parameter`.

The original ZTE build script uses NX563J-specific DTBs:

- `msm8998-v2.1-mtp-NX563J.dtb`
- `msm8998-v2-mtp-NX563J.dtb`
- `msm8998-mtp-NX563J.dtb`

and produces `Image.gz-dtb`.

## Existing mainline-oriented work

A key finding is that NX563J already has non-trivial mainline work.

The mainline-oriented DTS identifies:

- model: Nubia Z17
- compatible: `nubia,nx563j`, `qcom,msm8998`
- MSM ID: `0x124 0x20001`
- board ID: `0x08 0x00`
- 1080x1920 boot framebuffer
- Synaptics RMI4 touchscreen on I2C
- WCN3990 Bluetooth on UART
- Qualcomm power/regulator and reserved-memory definitions
- GPU / display / peripheral bring-up work

This means the mainline stage should be treated as continuation/cleanup/upstreaming of an existing port, not a fresh port.

## Mainline firmware

`firmware-mainline-nubia-nx563j` explicitly states that its files are intended for Wi-Fi and Bluetooth on mainline Linux and should be installed under `/lib/firmware`.

## MSM8998 upstream reference

Mainline Linux already contains OnePlus 5/5T MSM8998 device trees. They are useful as a maintained reference for:

- Qualcomm MSM8998 clocks/regulators
- UFS
- remoteproc/firmware
- WCN3990
- simple-framebuffer/display transition
- bootloader memory reservations

They should be used for comparison, but NX563J-specific GPIOs, panel, touch and board IDs must come from the Nubia port/downstream tree.

## Build policy

Do not vendor a full kernel checkout into this repository. CI should clone pinned upstream sources. This repo should contain:

- patches / overlays / configs we own
- reproducible build scripts
- device probe tooling
- documentation
- packaging and validation logic

This keeps the local Mac project small and pushes CPU/disk-heavy work to GitHub Actions.


## 2026-09-07 updated mainline assessment

The phrase "mainline" needs to be split into two different targets.

### Existing NX563J 6.0 port

The existing NX563J work around Rikivt / LemonFan / postmarketOS is based on a Linux 6.0 MSM8998 mainline-oriented fork. It is useful because it already carries Nubia-specific DTS and driver work and is now confirmed to build reproducibly in this project's GitHub Actions.

This should be treated as the bring-up bridge for the mainline path, not the final kernel target.

### Newer generic mainline

postmarketOS also ships newer generic/mainline kernel packages containing MSM8998 DTBs for devices such as OnePlus 5/5T, Sony Xperia and Xiaomi Mi 6-class hardware. NX563J is not present in that generic DTB set.

Therefore the long-term porting task is:

1. establish a bootable and diagnosable NX563J baseline using the existing 6.0-oriented port;
2. inventory which NX563J-specific nodes and patches are still outside newer mainline;
3. migrate the Nubia DTS and only the required board-specific fixes onto a newer generic upstream kernel;
4. keep firmware blobs separate under the standard `/lib/firmware` layout;
5. retire the private 6.0 fork once the required hardware works on the newer kernel.

## Live hardware facts from the connected phone

The connected device confirms several assumptions from public trees:

- board/platform: `msm8998`
- kernel boot device: `1da4000.ufshc`
- panel cmdline identifies `jdi_r63452_1080p_5p5_cmd`
- Android USB controller: `a800000.dwc3`
- system partition: `/dev/block/sda9`
- vendor partition: `/dev/block/sde41`
- boot/recovery/recovery2 are separate 64 MiB partitions on UFS LUN `sde`

The phone currently runs an older Nubia Android 10 stack with kernel `4.4.194-perf+`, so the LineageOS 4.4.302 branch is also a useful modernization step even before switching kernel families.


## Recovery / bootloader path

Official TWRP currently lists Nubia Z17 / NX563J as supported and documents the Nubia-specific bootloader command:

`fastboot oem nubia_unlock NUBIA_NX563J`

The connected phone currently reports `ro.boot.flash.locked=1`, so the project must treat bootloader unlocking as a future destructive transition, not as an inventory step.

Before any unlock operation:

1. keep the current boot/recovery/recovery2 images and their hashes;
2. back up user data that must survive a factory reset;
3. enter fastboot only to inspect device/bootloader variables first;
4. verify whether `fastboot boot <image>` is accepted before writing a partition;
5. only unlock if the Linux test path actually requires it and the data-loss implications are accepted.

Current public install documentation also confirms `Volume Down + Power` as the bootloader/fastboot key combination for NX563J.
