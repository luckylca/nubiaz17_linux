# Progress

Last updated: 2026-09-07

> **Current authoritative status:** the live inventory, backups, both kernel CI paths, and signed boot repacking are already complete. The "Current blocker" and "Next actions" sections below reflect the remaining device-side work.

## Current authoritative status

- Full 64 MiB read-only backups of `boot`, `recovery`, and `recovery2` are captured and hashed under the gitignored Mac backup directory.
- The existing NX563J Linux 6.0-oriented bridge builds successfully and its extracted kernel outputs are bit-for-bit reproducible across independent GitHub Actions runs `34096169661` and `34098047345`.
- LineageOS 4.4.302 downstream also builds successfully and its extracted kernel outputs are bit-for-bit reproducible across independent runs `34096169657` and `34098047268`.
- The reproducible downstream `Image.gz-dtb` SHA-256 is `e9f330df487d2681fb6783526053feccba3290d1323556bcdea5c405484c7a4f`; it uses Linux `4.4.302-perf+` with Android Clang r450784d / Clang 14.0.6.
- `scripts/repack_signed_boot.sh` is committed and produces bit-identical signed boot images for identical inputs.
- The current kernel-only smoke candidate is `nx563j-lineage-22.2-deterministic-kernel-only-smoke-signed.img`, size `15,426,856` bytes, SHA-256 `fc54ae2eb61c8c55d93f9c5a2aab8ace67f5298b6ed3025c8a7cf94658bf2a87`.
- Repacking that deterministic kernel twice produced the same SHA-256 `fc54ae2e...bf2a87`; both images have valid Android `/boot` signatures, exact CI kernels and the unchanged baseline Android ramdisk.
- The earlier smoke image SHA-256 `75b02e992020d501ae51c03791c4fdbd68958211626666c57aeb4cbe849305c4` is retained only as a historical pre-deterministic build and is superseded by the `fc54ae2e...` candidate.
- No device partition write, unlock, or flash has been performed.
- Read-only fastboot inspection is complete (2026-09-07): the bootloader is **already unlocked** (`unlocked: yes`) with secure boot still enforcing image signatures (`secure: yes`); non-A/B confirmed (all slot variables absent); `partition-size:boot = 0x4000000` (64 MiB); `max-download-size = 512 MiB`; `hw-revision = 20001`. Full output archived locally under `artifacts/fastboot-probe-2026-09-07/`.
- `fastboot boot <image>` is **not implemented** by the NX563J Nubia bootloader: the image transfers successfully but the boot command itself fails with `FAILED (remote: 'unknown command')`. Public NX563J sources (TWRP/LineageOS docs, XDA, 4PDA) confirm this device family only supports flash-based installation.
- A user-authorized flash of the signed smoke image to `recovery` was **rejected by the bootloader**: `Flashing is not allowed in Lock State`. `fastboot oem device-info` shows a two-tier lock: `Device unlocked: true` but `Nubia fastboot unlocked: false`. Opening the flash gate requires `fastboot oem nubia_unlock NUBIA_NX563J` (expected to factory-reset userdata) or an EDL/9008 flash path — both pending explicit user decision. No partition content was modified.
- CI now pins exact kernel source revisions and records resolved source commits in new artifacts: downstream `cda6a278ffa94c5a6aa428c4ab98b8ba0356c0d6`, 6.0-oriented bridge `a07b78d3526376cfb8ef136bd0fa279163ac5e3f`.

## Fixed target

Device: Nubia Z17 / NX563J  
SoC: Qualcomm MSM8998 / Snapdragon 835  
Architecture: arm64  
Primary use: small server + touch HMI

Priority hardware:

1. UFS
2. SSH / network access
3. display
4. touchscreen
5. Wi-Fi
6. Bluetooth

Not first-stage blockers: camera, calls, VoLTE, full Android hardware parity.

## Completed

- Created the local Mac project at `/Users/lucky/Desktop/project/nubiaz17_linux`.
- Connected it to `https://github.com/luckylca/nubiaz17_linux`.
- Confirmed the GitHub repository was initially empty.
- Recovered the previous two-stage plan: downstream baseline first, mainline afterwards.
- Confirmed LineageOS currently carries an NX563J MSM8998 kernel at Linux 4.4.302.
- Confirmed `lineageos_nx563j_defconfig`, `Image.gz-dtb`, 4096-byte boot page size and 64 MiB boot partition assumptions from current LineageOS device configuration.
- Found the original ZTE/Nubia NX563J kernel build script and its three board DTBs.
- Found existing NX563J mainline-oriented work, including a `qcom/msm8998-nubia-nx563j.dts` and postmarketOS packaging.
- Found a dedicated mainline firmware repository for NX563J Wi-Fi/Bluetooth.
- Added local device probing and GitHub Actions build scaffolding.

## Current blocker

The NX563J bootloader neither supports non-writing `fastboot boot` nor accepts `fastboot flash` in its current state (`Nubia fastboot unlocked: false`). Running any custom image on hardware requires either the documented `fastboot oem nubia_unlock NUBIA_NX563J` (expected userdata factory reset) or EDL/9008 flashing. This is a user decision; software-side preparation continues meanwhile.

## Next device-side actions

1. User decides between `nubia_unlock` (wipes userdata) and the EDL path (no wipe, needs a verified MSM8998 firehose programmer).
2. Once flashing is possible: flash the deterministic signed smoke image (`fc54ae2e...bf2a87`) to `recovery`, boot it via `adb reboot recovery`, and capture diagnostics (screen state, ADB reappearance, USB enumeration).
3. Keep fastboot sessions short — the NX563J fastboot interface froze once after several commands and needed a power cycle.

## Next software actions

- Build a minimal diagnostic initramfs (busybox `/init`, devtmpfs, block/USB-gadget diagnostics) as the first Linux userspace.
- Establish a screen-independent diagnostic channel, prioritizing USB gadget serial/network over UART and pstore.
- Continue the long-term migration of NX563J-specific DTS/drivers from the 6.0-oriented bridge toward newer generic MSM8998 mainline.


## 2026-09-07 live device inventory

The phone is now visible over USB/ADB as Nubia NX563J / MSM8998.

Observed current software state:

- Android 10 (Nubia build 21.4.14)
- running kernel: `4.4.194-perf+` (2020 build)
- non-A/B layout (no slot suffix)
- boot device: Qualcomm UFS controller `1da4000.ufshc`
- current root filesystem is Android dm-verity/system-as-root based
- Magisk root shell is available

Boot security needs careful interpretation before any flashing:

- `ro.boot.flash.locked=1`
- `getprop ro.boot.verifiedbootstate` reports `green`
- kernel cmdline contains `androidboot.verifiedbootstate=orange`
- kernel cmdline also contains `androidboot.selinux=permissive`

Do not assume the bootloader state from only one of these signals.

Confirmed partition mapping and size highlights:

- `boot -> /dev/block/sde18` — 64 MiB
- `recovery -> /dev/block/sde19` — 64 MiB
- `recovery2 -> /dev/block/sde20` — 64 MiB
- `system -> /dev/block/sda9` — 6 GiB
- `vendor -> /dev/block/sde41` — 450 MiB
- `userdata -> /dev/block/sda10` — about 51.9 GiB
- modem / bluetooth / dsp / persist are separate partitions

A read-only baseline backup of the three bootable Android images was successfully copied to the Mac under the gitignored directory:

`backups/2026-09-07-baseline/`

All three are exactly 67,108,864 bytes and start with the Android boot image magic `ANDROID!`. SHA-256 checksums are stored locally in `SHA256SUMS`.

## CI status

Both GitHub Actions kernel paths are complete and bit-for-bit reproducible; see `docs/RESEARCH.md` for the full run IDs and output hashes:

- LineageOS downstream 4.4.302: runs `34096169657` / `34098047268`, `Image.gz-dtb` SHA-256 `e9f330df...c405484c7a4f`.
- NX563J 6.0-oriented bridge: runs `34096169661` / `34098047345`, `Image.gz` SHA-256 `e5bf0e73...13510b4002f`.

The deterministic signed kernel-only smoke image (`fc54ae2e...bf2a87`) is the current on-device test candidate.
