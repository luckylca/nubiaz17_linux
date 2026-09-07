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

## 2026-09-07 live fastboot probe

The phone was rebooted to its bootloader and inspected with `scripts/fastboot_readonly_probe.sh` (read-only `getvar` only; archived under `artifacts/fastboot-probe-2026-09-07/`):

- `unlocked: yes` — the bootloader is **already unlocked**. This contradicts the Android-side `ro.boot.flash.locked=1` property and confirms that Android properties must not be used to infer bootloader state. It is consistent with the stock kernel cmdline reporting `androidboot.verifiedbootstate=orange`.
- `secure: yes` — secure boot is active, so boot images still need a valid signature; the pinned NX563J signer remains required.
- No A/B support: `current-slot`, `slot-count`, `slot-suffixes`, `has-slot:boot` all return "Variable Not found".
- `partition-size:boot = 0x4000000` (64 MiB), `partition-type:boot = raw`.
- `max-download-size = 536870912` (512 MiB) — ample for the ~15 MiB smoke image.
- `product = msm8998`, `variant = MSM UFS`, `hw-revision = 20001`, `battery-voltage = 4291`.
- `version-bootloader` and `version-baseband` return empty strings; `is-userspace` is absent (no fastbootd).

### `fastboot boot` is not implemented

Sending the deterministic signed smoke image succeeded (`Sending 'boot.img' OKAY`), but the boot command itself failed with `FAILED (remote: 'unknown command')`. Public NX563J documentation (official TWRP device page, the LineageOS install guide, XDA and 4PDA threads) consistently shows this device family flashing recovery/boot images rather than temporarily booting them; Nubia's bootloader ships a reduced fastboot command set. There is no known way to run a non-writing temporary boot on this bootloader.

Consequence: the kernel smoke test requires flashing the signed image to `boot` (Android keeps its ramdisk in that image, so stock Android may still boot with the replacement kernel) or to `recovery` (stock Android boot path untouched; test by entering recovery via keys). Both are recoverable from the verified baseline backups but require explicit user authorization.

### Two-tier lock state: flashing is still blocked

A user-authorized attempt to flash the signed smoke image to `recovery` was rejected: `Writing 'recovery' FAILED (remote: 'Flashing is not allowed in Lock State')`. `fastboot oem device-info` reveals a two-tier lock model:

- `Device unlocked: true` — the standard AVB-level OEM unlock has been done at some point (consistent with the `orange` verified boot state and with the Magisk-patched boot image running).
- `Nubia fastboot unlocked: false` — Nubia's own flash gate is still closed, and it is this gate that blocks `fastboot flash`.
- `Device critical unlocked: false`, `Verity mode: true`.

The documented way to open the Nubia flash gate is `fastboot oem nubia_unlock NUBIA_NX563J` (the same command on the official TWRP page). Like other bootloader unlocks it is expected to factory-reset `userdata`, so it remains a destructive, user-authorized step. Since `unlocked: yes` at the AVB level, signature enforcement on custom boot images is already relaxed (orange state); the signed smoke image is nevertheless the safest first payload.

An alternative that avoids both the unlock and the wipe is EDL (Qualcomm 9008) flashing with an MSM8998 firehose programmer — this is also the likely way the existing Magisk-patched boot was installed. It carries its own risks (wrong loader / wrong partition) and needs a verified NX563J/MSM8998 programmer.

Operational note: after several fastboot commands the device's fastboot interface froze and USB enumeration dropped until a power cycle — matching XDA reports of the NX563J fastboot screen freezing. Keep fastboot sessions short and prefer batching required commands.

### fastboot session behavior and the real unlock sequence (2026-09-07)

Extended device work revealed a repeatable pattern:

- A fastboot session answers commands only for a short window right after the bootloader (re)starts. If the device sits in fastboot for a while — or after a host-side transfer is killed mid-flight — the USB interface keeps enumerating (`fastboot devices`, `system_profiler` still see it, USB ID `18d1:d00d`) but every command hangs forever. Recovery requires the user to restart the bootloader from the on-device fastboot menu (or power-cycle) and the host must fire its commands **immediately** after re-enumeration. Cable replugs alone do not unwedge it.
- Do not run host-side polling loops that repeatedly open the fastboot interface (`getvar` monitors) concurrently with real fastboot operations — a hung polling child holds the interface and starves the real command (`< waiting for any device >` while `fastboot devices` still lists the phone).
- The first `fastboot oem nubia_unlock NUBIA_NX563J` attempt silently never executed (issued into a wedged session; the command hung and was killed). A later attempt in a fresh session succeeded instantly with `START update nubia fastboot unlock flag!!! / set state to 1 ok!!!`. Lesson: treat any hung fastboot command as NOT executed and re-run it in a verified-live session.
- With the Nubia flash gate open, `fastboot flash recovery <signed smoke image>` completed normally (`Sending OKAY`, `Writing OKAY`). `fastboot reboot recovery` is accepted by this bootloader but the device booted the stock `boot` partition anyway (kernel `4.4.194`), so use `adb reboot recovery` (BCB/misc) or hardware keys to actually land on the recovery partition.
- The Nubia flash gate (`Nubia fastboot unlocked`) is **not persistent**: `fastboot oem nubia_unlock NUBIA_NX563J` must be re-issued in every fastboot session before any flash. Each session: power-cycle into fastboot, fire `nubia_unlock`, then flash immediately — the interface stops answering after sitting idle.

## 2026-09-07 on-device bring-up results

### What works

- The deterministic downstream 4.4.302 kernel (`Image.gz-dtb`) boots on real NX563J hardware from the `boot` partition and reaches userspace. Full `dmesg` captured and healthy.
- The minimal initramfs (Debian arm64 busybox-static + `/init`) runs on both stock 4.4.194 and downstream 4.4.302 kernels.
- USB gadget: UDC `a800000.dwc3` binds from configfs; `ncm.usb0` and `mass_storage.usb0` work on both stock and downstream defconfigs (no ACM/serial/RNDIS/ECM — see `config/downstream-usb-diag.fragment` for a diag kernel). The composite gadget reaches `state=configured`; macOS enumerates the NCM interface and takes a DHCP lease from the on-device `udhcpd`.
- Diagnostics channel: the initramfs writes stage markers, `dmesg`, and system listings into raw sectors of the idle `recovery2` partition (`/dev/block/sde20`, user-authorized, baseline image backed up). Rooted stock Android reads them back with `dd`. This works regardless of screen, USB, or network state, and needs only the kernel's UFS driver.

### What does not work / dead ends

- Booting the stock-Android ramdisk with the replacement kernel (kernel-only smoke) fails in the Android userspace flow (`root=/dev/dm-0` dm-verity chain) — the device falls back to fastboot. The kernel itself is fine; the Android boot chain was never the goal.
- pstore/ramoops: stock kernel reserves `persistent_ram` regions but never registers a ramoops backend (nothing in `dmesg`, `/sys/fs/pstore` empty even after deliberate `sysrq-c`). Downstream DTB has no ramoops node. Do not rely on pstore on this device.
- Screen console: stock and downstream 4.4 defconfigs have `CONFIG_VT`/framebuffer console disabled, so `console=tty0` shows nothing. The bootloader appends `console=ttyMSM0,115200,n8 earlycon=msm_serial_dm,0xc1b0000` (stock cmdline), i.e. logs go to the DM UART — not accessible without opening the device.

### initramfs pitfalls hit (and fixed)

- `/init` has a `#!/bin/sh` shebang, and the kernel resolves the interpreter before userspace exists: the cpio must contain a real `/bin/sh -> busybox` symlink, otherwise the kernel panics with "No working init found" (silent black screen here).
- `busybox telnetd` needs devpts (`/dev/pts` + `/dev/ptmx`), otherwise connections drop instantly.
- Debian busybox-static arm64 (`busybox-static_1.35.0-4+deb12u1+b1_arm64.deb`, SHA-256 `732c9135...2a52f5`) runs fine on Kryo 280; pinned in `scripts/build_diag_initramfs.sh`.
- `busybox udhcpd` daemonizes by default; `mkfs.vfat`+loop mount of the log LUN works, but any hang there blocks gadget bind — keep LUN setup after network bring-up or well guarded.

## Boot image format and signing

The captured `boot` partition is a full 64 MiB dump, while the signed active Android boot image occupies only the beginning. The observed header-v0 geometry is: 4096-byte pages, kernel address `0x00008000`, ramdisk address `0x01000000`, legacy `second_addr=0x00f00000` even with `second_size == 0`, and tags address `0x00000100`.

The captured kernel is `14,043,025` bytes, the ramdisk is `1,308,415` bytes, the unsigned aligned payload is `15,360,000` bytes, and the signed active image is `15,361,320` bytes. At offset `15,360,000` the baseline contains an ASN.1 Android BootSignature for `/boot`.

Pinned boot tooling used for reproducibility:

- AOSP `mkbootimg`: `d2bb0af5ba6d3198a3e99529c97eda1be0b5a093`
- NX563J boot signer: `fa26cf3f625efbb772bb43c81cabd0ab7089a93e`
- signer certificate serial: `970F983909AA8949`
- signer certificate SHA-256 fingerprint: `8A:D1:27:AB:AE:82:85:B5:82:EA:36:74:5F:22:0A:B8:FE:39:7F:FB:3B:06:8D:F1:9C:A2:2D:12:2C:7B:3B:86`

Removing the existing signature and signing the unchanged payload again with that signer produces a byte-for-byte identical active image, SHA-256 `45d8a520b56e9a76b5d6faf7441ad9fed8dac2cdc06922a054c06da178dbd202`. Modern AOSP `mkbootimg.py` clears `second_addr` when there is no second image, so `scripts/repack_signed_boot.sh` explicitly restores the four legacy NX563J header bytes before signing.

## Verified downstream artifact and smoke image

This section records the earlier pre-deterministic successful build. Its kernel-only smoke image is superseded by the deterministic verification below.

GitHub Actions run `34090477218` produced the successful downstream artifact. The full artifact ZIP matches GitHub's published SHA-256 `b469fdf9f770f2c3a2932f29c2ac07636307e4cb9fd71e83fb4c6310334376a8`; its internal `SHA256SUMS` also validates all files after accounting only for the archive-relative path prefix used when the manifest was generated.

`Image.gz-dtb` has SHA-256 `45d8a24acfe0c74381c0a165345fa3b0d291370e80c04d11c89ba77b6cd9d9e1`, size `14,107,665` bytes, and contains three structurally valid NX563J DTBs. The current Android kernel payload also contains three concatenated valid DTBs, so downstream boot packaging must retain the complete `Image.gz-dtb`, not a bare `Image.gz`.

The first kernel-only signed smoke image has SHA-256 `75b02e992020d501ae51c03791c4fdbd68958211626666c57aeb4cbe849305c4` and size `15,426,856` bytes. Its BootSignature is valid, its unpacked kernel is byte-identical to the verified CI `Image.gz-dtb`, and its unpacked ramdisk is byte-identical to the baseline Android boot ramdisk.

## Diagnostic caveat: pstore

The successful downstream config enables `PSTORE`, `PSTORE_CONSOLE`, `PSTORE_PMSG`, and `PSTORE_RAM`, but `CONFIG_SERIAL_MSM_CONSOLE` is disabled. The current Nubia Android DTBs expose a standard ramoops region at `0xb0000000` with size 2 MiB, while the downstream DTBs reserve `0xaff00000` with size 1 MiB as `pstore_reserve_mem` and do not expose the same inspected `/soc/ramoops` node. Therefore retained pstore logs after a failed temporary boot are not yet guaranteed and must not be the only diagnostic channel.

## Reproducible source revisions

The workflows now default to exact source revisions instead of moving branches:

- LineageOS downstream: `cda6a278ffa94c5a6aa428c4ab98b8ba0356c0d6`
- existing NX563J 6.0-oriented bridge: `a07b78d3526376cfb8ef136bd0fa279163ac5e3f`

Manual workflow dispatch still accepts a commit, branch, or tag. New artifacts record both the requested ref and the resolved source commit.

## Deterministic rebuild verification

The workflows derive `SOURCE_DATE_EPOCH` and `KBUILD_BUILD_TIMESTAMP` from the resolved kernel source commit and fix `KBUILD_BUILD_USER=nx563j-ci`, `KBUILD_BUILD_HOST=github-actions`, and `KBUILD_BUILD_VERSION=1`.

### Downstream 4.4.302

Two independent GitHub Actions builds used pinned source `cda6a278ffa94c5a6aa428c4ab98b8ba0356c0d6`: round 1 was run `34096169657`; round 2 was run `34098047268`.

Extracted outputs are byte-identical across both runs:

- `Image.gz-dtb`: `e9f330df487d2681fb6783526053feccba3290d1323556bcdea5c405484c7a4f`
- `msm8998-mtp-NX563J.dtb`: `40d78302b7abbbed8214bdcf277355b5ede55a7d107e1f0f63110389812d0bc5`
- `msm8998-v2-mtp-NX563J.dtb`: `b5c332806e12c001d7ad06489b8fb48a19722d2599a32344ebd967c346f397ea`
- `msm8998-v2.1-mtp-NX563J.dtb`: `cabb6abec24982e7914a08f31b4934d6c6e2cf0e2f9263a1a56857216d1afed6`
- `kernel.config`: `fd04285db4ca7a4b6cd122738f218a3b59b1317e8dcfd4d0d2978c63f8034e9b`

The embedded build identity is fixed to `nx563j-ci@github-actions` and source time `Sun Aug 23 13:41:27 UTC 2026`.

### NX563J Linux 6.0-oriented bridge

Two independent GitHub Actions builds used pinned source `a07b78d3526376cfb8ef136bd0fa279163ac5e3f`: round 1 was run `34096169661`; round 2 was run `34098047345`.

Extracted outputs are byte-identical across both runs:

- `Image.gz`: `e5bf0e737d8e83df7a57e4d1d81d8a73d0949528f3e8ab7ce984a13510b4002f`
- `msm8998-nubia-nx563j.dtb`: `49cb986073909988b271b658b51cf18eda9fe2f0a11100071be20a559deac64a`
- `kernel.config`: `57e9e36b849a899e2f82ecb9e32a7fd76ed4f212caa1748070149207a9d62a83`

The embedded build identity is fixed to `nx563j-ci@github-actions` and source time `Sun Jun 8 05:03:13 UTC 2025`.

GitHub's uploaded artifact ZIP digests differ between runs because each run has a separate upload container. The reproducibility claim is intentionally about the extracted kernel, DTB, config, and source-metadata outputs, which are byte-identical.

## Deterministic signed smoke boot

Using the reproducible downstream `Image.gz-dtb`, the baseline Android ramdisk and the pinned NX563J signer produces:

- `nx563j-lineage-22.2-deterministic-kernel-only-smoke-signed.img`
- size: `15,426,856` bytes
- SHA-256: `fc54ae2eb61c8c55d93f9c5a2aab8ace67f5298b6ed3025c8a7cf94658bf2a87`

The image verifies with the NX563J Android `/boot` signature. Re-running the complete repack/sign process with identical inputs produced the exact same SHA-256, so the signed smoke-image packaging path is also bit-for-bit reproducible.

The earlier smoke SHA-256 `75b02e992020d501ae51c03791c4fdbd68958211626666c57aeb4cbe849305c4` came from the pre-deterministic kernel build and is no longer the preferred test candidate.

## 2026-09-08 persistent rootfs boot + SSH

Boot flow now flashed to `boot` (`nx563j-diag-rootfs-signed.img`, SHA-256
`a0e81e7558ca8374f806d05492f6b64169f1c4256bac4685ff8e43350cd2fee0`):

1. initramfs brings up the NCM gadget, usb0 `10.42.0.1`, udhcpd, telnetd.
2. initramfs mounts userdata (`/dev/sda10`, ext4 driver on the ext3-made fs)
   at `/mnt/rootfs`, bind-mounts `/dev` `/proc` `/sys`, mounts devpts inside.
3. initramfs runs `chroot /mnt/rootfs /root/rc.boot`, which sets the hostname,
   generates persistent dropbear host keys on first boot, and starts
   `dropbear -E -p 22`.

Because dropbear is started chrooted, SSH sessions land directly in the
Alpine rootfs with `/` = sda10. Rootfs-side changes (new services in
`rc.boot`) no longer require reflashing the boot image.

Access: `ssh -i work/nx563j_key root@10.42.0.1` (key auth; root password
`nx563j` also enabled). telnet on port 23 remains as fallback.

Lessons recorded:

- **busybox `reboot` ignores the reason argument** (verified for Debian
  busybox-static 1.35 and Alpine busybox 1.36.1): `reboot bootloader` just
  reboots normally. Entering fastboot from a Linux shell requires the raw
  `reboot(LINUX_REBOOT_CMD_RESTART2, "bootloader")` syscall. The 175-byte
  static stub in `tools/reboot-bootloader/` (hand-assembled, wrapped in a
  minimal ELF64 by `build_reboot_bl.sh`, no cross-binutils needed) does this
  and is proven on device.
- **No `sftp-server` / `scp` on the Alpine minirootfs**, so OpenSSH `scp`
  fails ("Connection closed"). Transfer files with
  `ssh ... 'cat > /path' < localfile` (or the foreground `nc` pattern).
- The dropbear host keys persist in `/etc/dropbear/` on sda10, so host
  identity is stable across reboots.
- `mkfs.vfat` is absent from the Debian busybox-static build, so the
  mass-storage log LUN is skipped at boot (sde20 raw-sector logging remains
  the primary side channel and is unaffected).
- Curiosity, not a problem: the freshly made userdata filesystem reports
  ~21 GiB used although the Alpine install is tiny — mkfs wrote fresh
  metadata over the old Android userdata without zeroing, and the ext
  accounting reflects that. 29.7 GiB free is plenty; revisit if the rootfs
  is ever recreated (zero the first sectors or use `mke2fs -E lazy_itable_init=0`
  and discard first).
