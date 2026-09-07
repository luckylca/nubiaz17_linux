# nubiaz17_linux

Linux bring-up and long-term mainline work for the Nubia Z17 (NX563J, Qualcomm MSM8998 / Snapdragon 835).

## Project goal

Turn the Nubia Z17 into a reliable small Linux server / touch HMI. The first-priority hardware is:

- UFS storage
- USB networking / SSH
- display
- touchscreen
- Wi-Fi
- Bluetooth

Camera, cellular calling, VoLTE and full Android-phone parity are not first-stage requirements.

## Strategy

### Stage 0 — non-destructive inventory

Collect the exact device state through ADB / fastboot before changing flash contents. Save partition layout, boot properties, kernel information and copies/hashes of boot-critical partitions.

### Stage 1 — downstream Linux 4.4.302 baseline

Use the actively maintained LineageOS Nubia MSM8998 kernel as the fastest path to a bootable hardware baseline.

Default references:

- kernel: `LineageOS/android_kernel_nubia_msm8998`, branch `lineage-22.2`
- device: `LineageOS/android_device_nubia_nx563j`
- defconfig: `lineageos_nx563j_defconfig`
- kernel image: `Image.gz-dtb`
- boot image page size: 4096
- boot partition size: 64 MiB

The initial userspace target is a minimal Linux rootfs suitable for SSH and services (Alpine/OpenRC or Debian).

### Stage 2 — mainline-oriented NX563J

Continue from existing NX563J mainline work rather than starting a device tree from scratch.

Important references include:

- `Rikivt/linux` NX563J mainline work
- `LemonFan-maker/MSM8998-OH-KERNEL-6.0` (contains `msm8998-nubia-nx563j.dts`)
- `MarshJiang/postmarket_nubia_nx563j`
- `MarshJiang/firmware-mainline-nubia-nx563j`
- upstream MSM8998 / OnePlus 5/5T DTS work

The existing NX563J mainline DTS already contains work for the panel/framebuffer, Synaptics RMI4 touch, WCN3990 Bluetooth and other board-specific devices.

## Local vs CI

The Mac is used for:

- source editing
- ADB / fastboot inspection
- image unpacking / repacking
- device-side smoke tests
- logs and recovery work

GitHub Actions is used for:

- full kernel builds
- repeated cross-toolchain builds
- mainline/downstream build matrices
- artifact generation

Workflows live under `.github/workflows/`.

## Safety rule

Do not flash a generated image merely because it compiles. The intended order is:

1. identify the exact connected device;
2. save the original boot-related images and partition metadata;
3. build and inspect artifacts;
4. prefer a temporary `fastboot boot` test when the bootloader supports it;
5. only then consider writing a partition.

## Current status

See [docs/PROGRESS.md](docs/PROGRESS.md).
