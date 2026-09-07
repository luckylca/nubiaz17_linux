# Progress

Last updated: 2026-09-07

> **Current authoritative status:** the live inventory, backups, both kernel CI paths, and signed boot repacking are already complete. Any older "current blocker" or "next action" text further down that says these are still pending is superseded by this section.

## Current authoritative status

- Full 64 MiB read-only backups of `boot`, `recovery`, and `recovery2` are captured and hashed under the gitignored Mac backup directory.
- The existing NX563J Linux 6.0-oriented bridge builds successfully in GitHub Actions.
- LineageOS 4.4.302 downstream also builds successfully; run `34090477218` produced a verified `Image.gz-dtb` artifact.
- The downstream build uses Linux `4.4.302-perf+` with Android Clang r450784d / Clang 14.0.6.
- `scripts/repack_signed_boot.sh` is committed and reproduces the original signed boot active image bit-for-bit when given the original kernel and ramdisk.
- The first kernel-only signed smoke image is generated and statically verified: `nx563j-lineage-22.2-kernel-only-smoke-signed.img`, size `15,426,856` bytes, SHA-256 `75b02e992020d501ae51c03791c4fdbd68958211626666c57aeb4cbe849305c4`.
- That smoke image has a valid Android `/boot` signature; its unpacked kernel exactly matches the verified CI `Image.gz-dtb`, and its ramdisk exactly matches the baseline Android boot ramdisk.
- No device partition write, unlock, or flash has been performed.
- The phone is currently absent from ADB/fastboot, so the next device milestone is a read-only fastboot-state inspection followed, if accepted, by non-writing `fastboot boot <signed-image>`.
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

The Mac has a working Android platform-tools install:

`/Users/lucky/Library/Android/sdk/platform-tools/adb`

but the phone is currently not enumerating as an Android/Qualcomm USB device:

- `adb devices -l`: no device
- `fastboot devices -l`: no device
- macOS USB inventory: no Nubia / NX563J / Android / Qualcomm match

This is below the ADB authorization layer; the USB device itself is not presently visible to macOS.

## Next device-side actions

Once USB enumeration appears:

1. run `scripts/device_probe.sh`;
2. record serial/model/build/bootloader state;
3. dump the exact by-name partition map;
4. identify boot/recovery/system/vendor/userdata layout;
5. capture original boot and recovery images where permissions allow;
6. hash all captured images;
7. determine whether temporary `fastboot boot` is accepted.

## Next software actions

- Make downstream CI compile `Image.gz-dtb` reproducibly.
- Make mainline-oriented CI compile the existing NX563J DTS branch.
- Add boot image unpack/repack tooling after an original boot image is captured.
- Add rootfs generation only after storage/boot strategy is fixed from the real device.


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

### Mainline-oriented

GitHub Actions run `34084661436` completed successfully.

It successfully:

1. cloned `LemonFan-maker/MSM8998-OH-KERNEL-6.0`;
2. configured `nx563j_oh_defconfig`;
3. built the kernel and DTBs;
4. uploaded the `nx563j-mainline-oriented` artifact.

This proves the existing NX563J 6.0-oriented tree is reproducibly buildable in our repository CI.

### Downstream 4.4.302

The first CI attempt exposed obsolete CI/toolchain URLs and empty workflow inputs on push; both were fixed.

The second attempt reached the real kernel build. It failed while linking the AArch32 vDSO because Clang selected the host x86 `/usr/bin/ld` for `armelf_linux_eabi`.

A third CI attempt now explicitly points the compat Clang target/linker search at the Android ARM32 binutils. This is the current downstream build under validation.
