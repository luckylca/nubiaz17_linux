# Progress

Last updated: 2026-09-08

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
- A user-authorized flash of the signed smoke image to `recovery` was initially rejected (`Flashing is not allowed in Lock State`; `Nubia fastboot unlocked: false`). The user then authorized the documented unlock: `fastboot oem nubia_unlock NUBIA_NX563J` was executed (2026-09-07); the device accepted it, wiped userdata, and returned to fastboot. The recovery flash is being retried once the post-wipe bootloader settles (it temporarily stopped answering fastboot commands while formatting — only `fastboot devices`, a host-side query, responded).
- A minimal diagnostic initramfs now exists: `initramfs/init` brings up a configfs USB composite gadget (serial shell, NCM/ECM/RNDIS network with DHCP+telnet, read-only log LUN) and dumps full boot diagnostics; `scripts/build_diag_initramfs.sh` packs it deterministically (pinned Debian arm64 busybox-static); `scripts/build_diag_boot.sh` wraps `repack_signed_boot.sh` into a signed diag boot image. First signed diag image: 15,107,368 bytes, SHA-256 `ffc34ec22638bb36e9df7d96ccfc8f480aaa1e4bc9f7b79edb48787e2f7c518f`, valid NX563J signature.
- The downstream workflow accepts an optional `config_fragment`; `config/downstream-usb-diag.fragment` enables devtmpfs and USB gadget serial/ACM/RNDIS/ECM so the diag kernel offers more channels than the stock defconfig (which lacks gadget serial/RNDIS and devtmpfs).
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

None. The first Linux userspace boots on real hardware with an interactive USB-network shell. All remaining work is forward development, not unblocking.

## Next device-side actions

1. Keep the rootfs-booting diag image in `boot` while developing (restore baseline `boot` only when stock Android is needed).
2. Harden the Alpine rootfs as a server: package set, services in `/root/rc.boot` (or migrate to OpenRC/switch_root), storage layout for data.
3. Bring up display (JDI R63452) and touch (Synaptics RMI4).

## Next software actions

- Run the downstream CI with `config/downstream-usb-diag.fragment` to add gadget serial/RNDIS/devtmpfs to the diag kernel (needs `gh auth login` on the Mac).
- Migrate the boot flow from busybox-PID1+chroot toward switch_root into the Alpine rootfs with OpenRC service management.
- Investigate display bring-up (JDI R63452 panel via downstream mdss, or simple-framebuffer) and Synaptics RMI4 touch.
- Continue the long-term migration of NX563J-specific DTS/drivers from the 6.0-oriented bridge toward newer generic MSM8998 mainline.


## 2026-09-08 persistent Linux rootfs with SSH at boot

**The phone now boots straight into a persistent Alpine Linux system on userdata and serves SSH over USB — no manual steps after power-on.**

- New flashed image: `nx563j-diag-rootfs-signed.img` (proven deterministic downstream 4.4.302 kernel `e9f330df...c405484c7a4f` + new initramfs), SHA-256 `a0e81e7558ca8374f806d05492f6b64169f1c4256bac4685ff8e43350cd2fee0`.
- Boot chain (verified end-to-end over two reboots via the sde20 stage log): initramfs → NCM gadget `10.42.0.1` + DHCP + telnetd → mounts `/dev/sda10` at `/mnt/rootfs` → bind-mounts dev/proc/sys + devpts → `chroot /mnt/rootfs /root/rc.boot` → dropbear on `:22` with persistent host keys.
- SSH lands chrooted directly in the Alpine rootfs (`/` = 51 GiB userdata, ext4): `ssh -i work/nx563j_key root@10.42.0.1`, root password `nx563j`. Key auth and password auth both verified; Alpine 3.20.3, `uid=0`.
- `rc.boot` lives in the rootfs, so service changes no longer require reflashing `boot`.
- New tool `tools/reboot-bootloader/`: a 175-byte static aarch64 ELF issuing `reboot(RESTART2, "bootloader")` — the only way to reach fastboot from a Linux shell (busybox `reboot` ignores the reason argument). Proven on device; build is bit-reproducible (`e73ee00e...c0585c764`).
- Full stage log this boot: `init alive → ncm ok → UDC bound → usb0 up (0s) → rootfs mounted (0s) → rc.boot done → diag ready`.

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

## 2026-09-07 first Linux shell on device

**The phone now boots the deterministic downstream 4.4.302 kernel into a Linux userspace with an interactive root shell over USB.**

- Boot path: `nx563j-diag-net-signed.img` (downstream `Image.gz-dtb` + busybox initramfs, NX563J-signed) flashed to `boot`; NCM gadget enumerates, `udhcpd` serves the host, `telnetd` (with devpts mounted) gives a shell at `10.42.0.1:23`.
- Verified from the on-device shell: `Linux 4.4.302-perf+ #1 SMP PREEMPT Sun Aug 23 13:41:27 UTC 2026 aarch64`, `uid=0`, and the complete UFS partition table (`sda9` system 6 GiB, `sda10` userdata ~52 GiB, `sde18` boot, `sde19` recovery, `sde20` recovery2, `sde41` vendor).
- Diagnostics belt-and-suspenders: sde20 raw-sector logging (works even if USB/network fails) + read-only mass-storage log LUN + NCM shell.
- To return to stock Android at any time: fastboot session → `nubia_unlock` → `fastboot flash boot backups/2026-09-07-baseline/boot.img`.

## 2026-09-07 on-device breakthrough

The replacement kernel boot question is resolved:

- **The deterministic downstream 4.4.302 kernel boots on real NX563J hardware and reaches userspace.** Earlier black-screen/fastboot-fallback results were userspace problems, not kernel problems: the Android-ramdisk smoke image fails in the Android boot flow (`root=/dev/dm-0` dm-verity chain), and the first diag initramfs had a missing `/bin/sh` symlink (kernel `binfmt_script` could not start `/init` at all).
- **A reliable screen-free diagnostic channel now exists**: the diag initramfs writes stage markers, full `dmesg`, and system listings into raw sectors of the idle `recovery2` partition (`/dev/block/sde20`, user-authorized, baseline-backed-up), readable afterwards from rooted stock Android. Stock-kernel and downstream-kernel probe runs both produced complete logs this way.
- **USB gadget works on both kernels**: UDC `a800000.dwc3` binds; `ncm.usb0` and `mass_storage.usb0` functions instantiate; the composite device reaches `state=configured` on the host. Stock and downstream defconfigs both lack gadget serial/ACM/RNDIS/ECM and devtmpfs (fragment for a diag kernel exists in `config/downstream-usb-diag.fragment`).
- pstore/ramoops is a dead end on this device: stock kernel reserves `persistent_ram` regions but never registers a ramoops backend (empty `dmesg` matches, empty `/sys/fs/pstore` even after deliberate `sysrq-c` panics), and the downstream DTB has no ramoops node at all.
- `fastboot oem nubia_unlock NUBIA_NX563J` must be re-issued **every fastboot session** before flashing; the Nubia flash gate does not stay open across reboots.
- Baseline `boot` was restored after each experiment; stock Android remains fully functional with Magisk root.

Current state: network-shell diag image (downstream 4.4.302 + initramfs, usb0 `10.42.0.1`, DHCP + telnetd, log LUN, sde20 logging) flashed to `boot` and under test.


Both GitHub Actions kernel paths are complete and bit-for-bit reproducible; see `docs/RESEARCH.md` for the full run IDs and output hashes:

- LineageOS downstream 4.4.302: runs `34096169657` / `34098047268`, `Image.gz-dtb` SHA-256 `e9f330df...c405484c7a4f`.
- NX563J 6.0-oriented bridge: runs `34096169661` / `34098047345`, `Image.gz` SHA-256 `e5bf0e73...13510b4002f`.

The deterministic signed kernel-only smoke image (`fc54ae2e...bf2a87`) is the current on-device test candidate.
