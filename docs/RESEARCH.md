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

## 2026-09-08 display bring-up (JDI R63452 cmd-mode panel)

**Linux now draws on the NX563J screen.** Recipe (all proven on device):

1. Panel: `qcom,mdss_dsi_jdi_r63452_1080p_5p5_cmd`, fb0 = `mdssfb_90000`,
   1080x1920 @ 32bpp, virtual height 3840 (double buffer), stride 4352,
   smem 16,711,680 bytes.
2. **Keep /dev/fb0 open.** With no fb client, mdss re-suspends the panel
   within ~1 s of unblank (`panel_status=suspend`). A long-lived holder
   process keeps it `alive`.
3. **The write() path is broken**: `dd of=/dev/fb0` fails with ENODEV
   ("No such device") even with the panel alive. Use mmap + draw +
   `FBIOPAN_DISPLAY` (tools/fbtest/fbtest.c).
4. **Backlight defaults to OFF.** `panel_status=alive` only means the fb
   layer is unblanked — the panel power-on sequence never re-runs (the one
   and only `incell_lcd_power_off` happens at final suspend; there is no
   matching power-on message after the splash handoff). The frame was being
   committed to the panel all along; the screen was simply unlit. Fix:
   write `/sys/class/leds/lcd-backlight/brightness` (and/or
   `/sys/class/leds/wled/brightness`, max 4095) while the panel is alive.
5. `msm_cmd_autorefresh_en=1` was set in the winning configuration
   (necessity not isolated; harmless).
6. `INFO: task mdss_dsi_event blocked for more than 120 seconds` reports
   are **benign**: dsi_event_thread idles in an uninterruptible
   `wait_event()` (`dsi_event_thread+0xc8`), which the hung-task watchdog
   flags by design. Not a wedge.

Boot-persistent: `/root/rc.boot` in the rootfs (reference copy:
`initramfs/rc.boot.rootfs`) starts dropbear, enables autorefresh, launches
`fbtest 999999` as the fb holder (draws red/green/blue/white bands as a
boot-success splash), and lights the backlight.

Operational footgun: `pkill -f "fbtest ..."` inside an ssh remote command
matches the sshd-spawned shell's own cmdline and kills the session (and
the newly started replacement). Use exact pgrep/pkill patterns or kill by
pid.

## 2026-09-08 touch investigation (Synaptics RMI4, in-cell) — root cause + fix in CI

Symptom on our kernel: `nubia_synaptics_dsx` probes OK at t≈1.5 s (reads
firmware id 3056304, registers input4), then **every I2C transaction from
t≈1.9 s onward NAKs** (`i2c-msm-v2: NACK: slave not responding` → -107
ENOTCONN), IRQ count stays 0, evdev reads return EIO, and the driver falls
into a "spontaneous reset detected" loop every ~0.6 s that never recovers.

Ruled out (all verified on the live device):

- Power: pm8998_l14 (vdd_lcd), l28 (vdd_ana), l6 (vcc_i2c), lab_reg and
  ibb_reg (5.5 V panel bias) all ENABLED with correct voltages and
  registered consumers. `Regulator lcd_reg is null` also prints on stock —
  red herring (that message is about the platform-device path; the I2C
  client supplies are claimed fine).
- `regulator_proxy_consumer_remove_all` timing: stock 1.99 s, ours 1.72 s —
  in BOTH cases after the touch probe registered its regulator votes.
- Firmware update leaving the IC in bootloader mode: no synaptics firmware
  file exists anywhere in stock's firmware paths and fwu is only triggered
  via sysfs (at t=17 s by Android userspace, ending in "Bootloader version
  mismatch" = no-op). Not the cause.
- `nubia_wakeup_gesture`: 0 by default on both.
- Full driver-managed rail cycle (fb blank 4 → 0) once: still NAK
  afterwards — but note l14 is shared with the panel, so the IC never got
  a TRUE full power cut that way.

Ground truth from stock Android (Magisk root, early dmesg captured by
rebooting and pulling dmesg the moment adbd appears — the ring wraps by
~19 s due to audit spam):

- Stock touch probe at 1.76 s, then **zero touch I2C until t=17 s**
  (fwu poke from userspace) and the fb-event resume at **t=18.5 s**, which
  succeeds after 2 retries ("retry 1, retry 2, resume workqueue finish").
- On OUR kernel the fb unblank fires at t≈1.9 s → resume pokes the IC
  ~1.9 s after boot → all reads NAK past the 3-retry limit → failed
  `reset_device` + the 0.6 s reset loop → IC never comes up.
- On an earlier diag boot (no early fb client), the first touch resume
  happened at **t=1312 s and SUCCEEDED after a few retries** — proving
  late first contact works and early first contact kills.
- Conclusion: the in-cell IC needs a settling window after boot; an early
  first poke (and the ensuing reset loop) leaves it permanently NAK until
  a real power cut.

Fix: `patches/downstream/0002-touch-resume-delay-until-ic-ready.patch` —
defers fb-notifier resumes until 20 s after boot, verifies the IC answers
on f01 afterwards, and on continued NAK cycles rails through suspend and
retries the full resume (8 × 5 s). CI applies all patches in
patches/downstream/ (sorted) and tags multi-patch artifacts `-patches`.
Push-triggered build, no gh auth needed.

Operational hazards discovered (avoid):

- Reading `/sys/kernel/debug/gpio` or regulator `consumers` debugfs while
  the touch driver is in its reset loop HANGS the reader in D state; the
  pileup wedges normal `reboot` (device_shutdown blocks on the stuck
  driver) — recover with `echo b > /proc/sysrq-trigger` (telnet fallback
  shell from the initramfs stays alive; dropbear may stop accepting).
- `unbind`/`bind` of `5-0020` after a long wedged period re-probes but
  deadlocks in `synaptics_creat_tpnode` (tpnode_class EEXIST from the
  first probe) — do not rebind this driver; reboot instead.
- A hung watchdog reboot can follow such D-state pileups.

Stock reference dumps: `artifacts/stock-android-probe-2026-09-08/`
(dmesg-stock-early.txt = full early boot, dmesg-stock.txt, regulators,
interrupts).

## 2026-09-08 touch part 2: two more stacked bugs (cascade + empty fn list)

The "early poke kills the IC" theory from the first analysis was
disproved by the deferred-resume experiment: with all I2C blocked until
t=20 s the IC still NAK'd at 20 s, and separately it survived untouched
from t=1.5 s to t=1312 s in another boot. The real failure chain has
three stacked layers, each unmasked in turn:

1. **Settling window (real)**: first contact before ~15-20 s NAKs;
   stock's first contact is at 17-18.5 s. Patch 0002 defers the fb-event
   resume to t>=20 s (`ktime_get_seconds()`, not jiffies — those start
   at -300*HZ).
2. **tp recovery cascade (destructive)**: on the last retry of any
   failed I2C read, the driver schedules `tp_reset_work`, which pulses
   the touch IC **reset GPIO**. Each GPIO reset restarts the IC's long
   settling window; the 0.5 s retry loop never lets it finish, so one
   transient NAK wedged touch for minutes or until reboot. The IC
   self-recovers whenever the loop leaves it alone (observed: dead
   20.6 s -> alive ~240 s; dead 3540 s -> alive ~3620 s; dead 3763 s ->
   alive ~3812 s — each time after the loop's >10-count cap gave it a
   quiet window). Patch 0003 forces `tp_recovery_enable = false` in
   `parse_dt`.
3. **Empty function-handler list (silent)**: `synaptics_rmi4_resume()`
   always ends with `reset_device()`, which **empties** the RMI4
   function handler list and re-queries the IC. When that query races
   the IC's own post-reset reboot (happened at t=20.5 s), the list
   stays empty forever: the IC is fully alive (ic_detect=1, firmware_id
   reads, 10 s cs2 polls succeed, attn irqs fire on every touch) but
   there is no F12 handler, so no input events are ever reported.
   Patch 0002 now also verifies `support_fn_list` is non-empty after
   the alive-check and rebuilds it with `reset_device()` once the IC
   is settled.

Debugging notes: musl `od`/`cat` on /dev/input/eventN exit with a bare
"read error" while the driver is in its wedged state (works fine when
healthy) — use `tools/touchdump/touchdump.c` (errno-reporting reader).
`pkill -f <pattern>` inside an ssh remote command matches the sshd
shell's own cmdline — kill by exact pid or use bracket globs.

## 2026-09-08 Wi-Fi: WCN3990 boots via modem subsystems (bring-up recipe)

Chain discovered from stock dmesg ground truth + live experiments:

1. qcacld is built-in but defers all init until userspace writes
   `ON` to `/dev/wlan` (the `qcwlanstate` char device, major 226).
   Even then, the icnss driver only probes qcacld once the **WLAN
   firmware** signals FW_READY over QMI.
2. The WCN3990 firmware runs as protection domain `wlan_pd` **under the
   modem** (`service-notifier: ... msm/modem/wlan_pd`). Stock boots the
   modem at t~19 s via the vendor peripheral manager; nothing boots it
   in a bare Linux userspace.
3. Opening and **holding** `/dev/subsys_modem` boots the modem
   (`subsys_device_open` -> `subsystem_get_with_fwname` -> PIL). Hold
   it open (refcounted; close = shutdown). Modem firmware files
   (mba.mbn, modem.b**) load via `firmware_class.path=/vendor/firmware_mnt/image`
   — works when the open() happens in the chroot context where that
   path exists on the rootfs.
4. With no ueventd, each missing firmware (msadp debug policy) costs
   one ~60 s user-helper timeout before the PIL continues — harmless,
   just slow. Confirmed full boot: `MBA boot done` -> `Brought out of
   reset` -> `Power/Clock ready` -> SSCTL QMI connected.
5. **Hazard: the modem boots, then ~30-90 s later the device hard-
   reboots** (silent, no panic output) — consistent with a modem fatal
   escalated by SSR at restart_level `system`. Probably missing
   userspace QMI peers (rmtfs/EFS; kernel has no CONFIG_QRTR). SSR
   restart levels are writable per-subsystem under
   `/sys/bus/msm_subsys/devices/subsys_*/restart_level`
   (`system`/`related`/`independent`) — set `related` before
   experimenting to survive modem crashes.
6. Stock bionic userspace (pm-service, pd-mapper) is runnable in
   principle: vendor partition (sde41) has the daemons; bionic
   linker/libc live in the runtime APEX on sda9
   (`system/apex/com.android.runtime.release`), reachable by
   bind-mounting it at `/apex/com.android.runtime` and sda9's
   `system/` at `/system`.

## 2026-09-08 Wi-Fi part 2: wlan0 UP — full chain root-caused

End state: `wlan0`/`wlan1`/`p2p0` exist, scan works on both bands.
Recipe: `tools/wifi-bringup/wifi-bringup4.sh`. Stock-comparison ground
truth in `artifacts/stock-wlan-probe-2026-09-08/dmesg-nx563j.txt`.

Observed stock timeline (t in s): ADSP connect 17.61 → modem out of
reset 19.58 → servreg 180-connect 19.83 → QMI_IPA_INIT req 20.01 →
"not send indication" 20.086 → uC WDI/NTN event-log handlers 20.091 →
resp 20.094 → Server 00001002 rejected 20.12 → **wlan_pd indication
state 0x1fffffff 20.52** → `icnss: QMI Server Connected: 0x981` 20.52
→ FW ready 23.16 → rmnet_data* register 21.16+.

Root causes fixed (in order found):

1. **/dev perms**: mdev leaves `/dev/null` `/dev/random` `/dev/urandom`
   0660 root:root; `/dev/null` was once a 35-byte regular file (a
   redirect ran before the node existed). pd-mapper (uid 1000)
   crash-loops on `/dev/urandom` EACCES, killing the whole
   service-locator chain (icnss's one-shot `init_service_locator`
   300 s timeout dies at -62 if pd-mapper is late). Fix:
   `mknod`/`chmod 0666` before any daemon. Verified by kprobe:
   `icnss_get_service_location_notify` fires with
   `msm/modem/wlan_pd` instance 180 (stock-identical), so pd-mapper's
   answer was always correct — the failures were all environmental.
2. **IPA uC is required on this kernel** (v3 "stock never loads uC"
   experiment disproven): MSM8998 is IPA 3.0/GSI, so
   `ipa3_plat_drv_probe` does NOT call `ipa3_post_init`; only the
   `/dev/ipa` write path (`ipa3_pil_load_ipa_fws` → queue
   `ipa3_post_init_work`) completes `init_completion_obj` and fires
   the ipa-ready callbacks. rmnet_ipa's probe blocks in
   `ipa_register_ipa_ready_cb` until then, so `ipa3_qmi_service_init`
   never runs → no `qmi_svc_event_notifier_register(0x31,...)` →
   `ipa3_q6_clnt_svc_arrive` never sends
   `QMI_IPA_INIT_MODEM_DRIVER_REQ_V01`. Live symptom: ipacm stuck
   120 s+ in `ipa3_ioctl: "IPA not ready, waiting for init
   completion"`. Stock DOES load the uC (its dmesg shows the uC
   event-log handlers answering the modem at 20.09).
3. **tftp RFS gates wlan_pd** (THE wlan_pd blocker): with the QMI_IPA
   handshake stock-identical, the modem still never started wlan_pd —
   no servreg indication, no WLFW service 0x45 in
   `msm_ipc_router/dump_servers`. Cause: `tftp_server` couldn't create
   its RFS dirs — `/vendor/rfs/msm/mpss/readwrite` is a symlink to
   `/mnt/vendor/persist/rfs/msm/mpss`, and persist (`/dev/sda2`, ext4,
   already populated: `WCNSS_qcom_cfg.ini`, `bluetooth/`, `rfs/`,
   uid 2903) was never mounted. The modem's boot-time RFS write check
   (`server_check.txt`) failed with ENOENT. Mounting persist RW +
   restarting tftp_server + bouncing the modem produced the
   stock-identical indication 0.7 s after EFS reads.
4. **qcacld ini load runs in initramfs fs context**:
   `hdd_wlan_startup` → `hdd_parse_config_ini` →
   `request_firmware("wlan/qca_cld/WCNSS_qcom_cfg.ini")` executes on
   `icnss_driver_event_work` (kworker → kthreadd → initramfs root).
   Files staged only in the chroot `/fwimage` are invisible; the
   request falls back to the usermode helper
   (`/sys/class/firmware/wlan!qca_cld!WCNSS_qcom_cfg.ini`, loading=0,
   no ueventd to answer), hangs 120 s, the FW watchdog then fails the
   probe: `icnss: Driver probe failed: -22`. Fix: stage
   `wlan/qca_cld/{WCNSS_qcom_cfg.ini,wlan_mac.bin}` (from
   `/vendor/firmware/wlan/qca_cld/`) under `/proc/1/root/fwimage/` as
   well.

Operational notes:

- Fake logd `tools/logcatd/logcatd.c` binds `/dev/socket/logdw`
  (SOCK_DGRAM) and parses the 24-byte `{id,tid,sec,nsec,uid,pid}`
  header + `[prio][tag\0][msg\0]` payload — bionic daemons
  (tftp_server, netmgrd, cnss-daemon, time_daemon) become observable.
- Modem bounce without reboot: scan `/proc/*/fd/*` for
  `/dev/subsys_modem`, `kill -9` the holder (usually pm-service; the
  script's own hold pid in `/tmp/modem.hold.pid` is a setsid parent,
  not the fd holder). MSS shuts down (`AFTER_SHUTDOWN`), the
  keepalive restarts pm-service, modem re-boots, whole wlan chain
  re-runs. `SIGTERM` is ignored by pm-service; use `kill -9`.
- pm-service (not the script) ends up holding `/dev/subsys_modem`
  once running; that is fine and stock-like.
- `icnss` unbind/bind does NOT re-probe (penv singleton survives
  remove → `-EEXIST Driver is already initialized`); use a modem
  bounce instead.
- `wpa_supplicant -B -i wlan0 -D nl80211` works from the Alpine
  rootfs; `wpa_cli scan/scan_results` verified (11 networks).
- ipacm loops `ipa3_setup_sys_pipe: EP 3 already allocated` /
  `handle3_egress_format failed` every 3 s — harmless for Wi-Fi
  (it's the WWAN offload path), present on all runs.


## 2026-09-09 Bluetooth: WCN3990 BT block alive — chip-POR power condition found

Architecture (from stock DTB decompiled out of
`backups/2026-09-07-baseline/boot.img` board v2.1 + stock kernel
IKCFG + vendor binaries):

- BT HCI is plain 4-wire UART on BLSP1_UART3 (`uart@c171000`,
  `/dev/ttyHS0`, pinctrl gpio45-48 `blsp_uart3_a`), powered by the
  btpower driver (`bt_wcn3990` node, 6 rails + `rf_clk2`,
  `/sys/class/rfkill/rfkill0` = `bt_power`). All values in the
  lineage DT are stock-identical (incl. the misleadingly-labelled
  `pmi8998_bob_pin1` whose regulator-name is correctly
  `pm8998_bob_pin1`).
- The **stock kernel also has `CONFIG_BT_HCIUART` unset**: stock
  Android talks HCI through the `wcnss_filter` USERSPACE daemon
  reading the TTY directly ("Step 7-ReaderThread-BT-SoC-To-Host"),
  with SoC init (TLV rampatch crbtfw21.tlv + NVM crnv21.bin from
  partition `bluetooth`=sde22, stock mount `/vendor/bt_firmware`)
  done by `/vendor/bin/hci_qcomm_init` (`-e` prints env, `-N` skips
  the final reset/baud restore, final baud 3000000).
- For Linux/BlueZ we want kernel `hci0` instead →
  `config/downstream-bt.fragment` adds `CONFIG_BT_HCIUART(+H4,+QCA)`,
  RFCOMM/BNEP/HIDP. The 4.4-era in-kernel `hci_qca.c` (IBS-only, no
  TLV) matches the userspace-TLV split exactly.

**The blocker and its root cause:** with all rails on (verified in
regulator_summary: s3=1352mV, s5=2040mV, l7=1800mV, l17=1304mV,
l25=3312mV, bob_pin1=3600mV), `rf_clk2_pin` enabled, UART DM loopback
passing, and pinctrl correctly switching sleep↔active on open, the
chip stayed completely silent on the UART (hci_qcomm_init timeouts,
zero bytes on power-cycle listen). Root cause: **the BT block inside
the WCN3990 package is only released at chip POR when the BT rails
are already on.** Our chip POR'd with the modem boot while rfkill0
was still blocked. Fix: `echo 1 > rfkill0/state` BEFORE the modem
boots, then bounce the modem → `hci_qcomm_init` immediately succeeds:
TLV download, baud 3M, chip MAC `00:a0:c6:c3:c9:3a`, EXIT=0.

`wifi-bringup4.sh` now unblocks the bluetooth rfkill in step 5b
(before the modem hold) and mounts sde22 at `/bt_firmware`; after
wlan0 appears it runs `hci_qcomm_init -e -N`. Remaining step: kernel
rebuild with `config/downstream-bt.fragment` (needs CI), then
`hciattach`/BlueZ to get `hci0`.

## 2026-09-09 Bluetooth part 2: kernel hci0 + BlueZ verified end-to-end

The CI rebuild with `config/downstream-usb-diag-bt.fragment` took four
rounds; each failure was a latent bug in code that had NEVER been
compiled in this tree (stock and the LineageOS defconfig both leave
HCIUART off, and no earlier CI run ever applied a fragment):

1. `hci_ldisc.c:492` referenced `hu->rx_lock`, a member `struct hci_uart`
   does not have here (partial backport leftover, unused elsewhere) →
   `patches/downstream/0005` deletes the stray `spin_lock_init`.
2. `btqca.c` (ROME TLV helpers) tripped clang `-Werror
   -Wpointer-bool-conversion` on `!edl->data` (zero-length array member,
   always false) at two TLV receive sites → `patches/downstream/0006`.
3. `configfs.c` failed with undeclared `gadget_index` / missing
   `gadget_info.dev` — i.e. compiled with `USB_CONFIGFS_UEVENT=n` even
   though the defconfig sets it. Root cause: the fragment also enabled
   `USB_G_SERIAL`/`USB_G_NCM`, legacy gadget drivers that share the
   "USB Gadget Drivers" Kconfig **choice** with `USB_CONFIGFS` (this
   tree sources `legacy/Kconfig` INSIDE the choice). Multiple y-members
   make choice resolution environment-dependent: locally it picked
   `USB_G_NCM` (killing configfs entirely), in CI it kept
   `USB_CONFIGFS=y` but revoked `UEVENT`. Fix: drop the legacy gadget
   lines from the fragment and pin `CONFIG_USB_CONFIGFS=y` explicitly.
   Verified by replicating `merge_config.sh` + `olddefconfig` locally.
4. `rndis.c:46` `KBUILD_MODNAME` undeclared: `rndis.o` is linked into
   THREE composite objects (`usb_f_rndis`, `usb_f_gsi`,
   `usb_f_qcrndis`); with F_GSI already on from the defconfig, adding
   F_RNDIS made rndis.o multi-composite so kbuild drops its
   `-DKBUILD_MODNAME`. Fix: no RNDIS in the fragment (the USB network
   link uses the defconfig's NCM anyway).

Also learned: `merge_config.sh` greps the whole fragment for `CONFIG_*`
tokens when printing override warnings — keep symbol names out of
fragment comments.

**Flashing:** `fastboot oem nubia_unlock NUBIA_NX563J` had to be
re-issued (the Nubia flash gate is per-session, as documented), then
the signed diag image with the BT kernel flashed to `boot` cleanly
(user-authorized).

**On-device verification (2026-09-09, all live):**
- Cold boot on the BT kernel: Wi-Fi autostart unaffected (wlan0
  associated, lease 192.168.1.186).
- The script-fired `hci_qcomm_init` FAILED with "read BT SoC timed out"
  while a manual run ~60 s later succeeded (`BTS_ADDRESS`, EXIT=0) —
  firing it the instant wlan0 appears races the BT block out of reset.
  The script now retries with backoff (6 × 10 s).
- `/root/hciattach-qca /dev/ttyHS0 3000000` (raw termios2 + CRTSCTS,
  N_HCI ldisc, HCIUARTSETPROTO QCA=8) → kernel registers
  `/sys/class/bluetooth/hci0` on `c171000.uart`.
- `hciconfig hci0 up` → **UP RUNNING**, BD Address `00:A0:C6:A3:43:4F`,
  70 commands/events, 0 errors.
- dbus + `bluetoothd` (BlueZ 5.76 from aliyun mirror): controller
  powered, alias `nx563j-linux`; **BLE scan discovers 9+ real devices
  with RSSI** — full RX/TX through the chip verified.
- bdaddr differs from the first readback (`...:c3:c9:3a` vs
  `...:a3:43:4f`): the NVM-programmed address is not stable across
  inits; if a fixed address matters, set it via `btmgmt public-addr`.

Operational notes:
- apk TLS: the device RTC sits at "Jan 2" so certificate notBefore
  checks fail; `http://mirrors.aliyun.com` repos work regardless.
  `ca-certificates` is now installed; HTTPS will validate once the
  clock is set (NTP/date).
- bluez + bluez-deprecated (hciconfig/hcitool/btattach) installed in
  the rootfs; bluetoothd lives at `/usr/lib/bluetooth/bluetoothd`.
- The udhcpc watcher raced once (lease logged, no address): it now
  verifies the address landed and retries up to 3×.
- `reboot2` (RESTART2 with mode string, e.g. `reboot2 bootloader`)
  built on-device at `/root/reboot2` — the path into fastboot without
  adbd (Android `/system/bin/reboot` hangs in the chroot).

## 2026-09-09 Bluetooth part 3: unattended cold-boot chain — the IBS trap

Automating the proven manual chain into `wifi-bringup4.sh` exposed three
more failure modes, one per boot cycle:

1. **mksh name-search**: inner `sh -c` subshells resolved to Android's
   `/system/bin/sh` (the script prepends `/vendor/bin:/system/bin` to
   PATH for the bionic daemons), and mksh could not exec musl binaries
   by name ("inaccessible or not found") while absolute paths worked.
   Fix: pin every inner subshell to `/bin/sh` with an explicit
   `PATH=/bin:/sbin:/usr/bin:/usr/sbin`.
2. **hci_qcomm_init vs chip POR**: fired right at wlan0-appearance it
   loses to the BT block still coming out of reset (all VS reads time
   out). A 45 s settle + at most 2 attempts 20 s apart is reliable; a
   killed mid-TLV attempt leaves the chip at an unknown baud, and
   killing a wedged hciattach live-locks the 4.4 hci_uart close path —
   so the script never kills the ldisc and gets it right on the first
   attach.
3. **kernel qca_setup vs userspace TLV**: three kernel revisions were
   needed (`patches/downstream/0007`):
   - *Unpatched* (full in-kernel EDL rome download): the chip, already
     initialized by `hci_qcomm_init`, answers the EDL version request
     with HCI status 0x0c (Command Disallowed) which `net/bluetooth/
     lib.c:86` maps to **EBUSY** → "Can't init device hci0: Resource
     busy". (On the manual-verify boot the kernel's request_firmware
     for `qca/rampatch_*.bin` happened to fail with -ENOENT, which the
     stock code treats as "run with original fw" — which is why the
     manual chain worked on the unpatched kernel.)
   - *v1* (skip baud dance + rome): **ETIMEDOUT** — hciattach puts the
     host at 3M but `hci_qcomm_init -e -N` leaves the chip listening at
     115200; without the VS set-baud handshake nothing is answered.
   - *v2* (dance kept, rome skipped, **IBS enabled**): **ETIMEDOUT** —
     the real trap. With `STATE_IN_BAND_SLEEP_ENABLED` set and
     tx_ibs_state starting at ASLEEP, `qca_enqueue` parks every
     post-setup frame in `tx_wait_q` and waits for a HCI_IBS_WAKE_ACK
     the userspace-initialized chip never sends (nothing ever configured
     IBS on the chip side), so `__hci_init`'s standard commands never
     reach the wire. The baud dance itself cannot fail in this tree —
     `qca_set_baudrate` is fire-and-forget with a 300 ms settle.
   - *v3* (final): baud dance kept, rome skipped, **IBS left off** —
     exactly the stock `-ENOENT` path that the working manual boot took.

## 2026-09-09 Bluetooth part 4: the Write-LE-Host-Supported lottery

With patch 0007 v3 the unattended chain reached `hci0 UP RUNNING` on
one cold boot — but the *next* cold boot failed every `hciconfig up`
with EBUSY again, this time with the chip clearly answering (124
events). A `btmon` trace (Alpine package `bluez-btmon`, also
`bluez-btmgmt`) pinned it exactly:

    > HCI Event: Command Complete (0x0e)
          Write LE Host Supported (0x03|0x006d) ncmd 1
            Status: Command Disallowed (0x0c)

The userspace NVM download (`crnv21.bin` via `hci_qcomm_init`) leaves
the chip with `LE_Host_Supported` already set — sometimes, depending
on how the NVM write lands across a chip reset (the same lottery that
randomizes the last three bdaddr octets each boot). The kernel's
`__hci_init` then sends a redundant Write LE Host Supported, the chip
answers 0x0c, `bt_to_errno` maps that to EBUSY
(`net/bluetooth/lib.c:86`), and the whole open aborts.

`patches/downstream/0008` makes the two touchpoints tolerant:
`hci_cc_write_le_host_supported` treats 0x0c as success for flag
state, and `hci_req_cmd_complete` no longer aborts the init request
on that opcode+status. The bit is already in the desired state, so
this is semantically a no-op.

Also fixed in the bring-up script: `/run` is now a fresh tmpfs at step
0. The persistent rootfs kept `/run/dbus/dbus.pid` across reboots, so
`dbus-daemon --system --fork` refused to start ("pid file exists")
and bluetoothd died with "D-Bus setup failed: Connection refused".

## 2026-09-09 polish round: NTP, dashboard v2, and three new traps

- **Clock**: the RTC rejects `hwclock -w` (EINVAL) and the system boots
  at 1970, breaking TLS. Fix: `ntpd -q -p ntp.aliyun.com` once the
  wlan0 lease lands (pool.ntp.org is unreachable from this network;
  aliyun's NTP works). HTTPS apk repos validated after the fix.
- **fbdash v2**: the framebuffer dashboard now also shows the wlan0
  address, BT state (`UP` + bdaddr via hciconfig scrape), and the
  wall-clock time. Compiled on-device (`gcc -O2 -static`).
- **Trap — sysrq 'b' loses unsynced writes**: a script deployed over
  ssh, read back with the right md5 (page cache), and then followed by
  a sysrq-b hard reset silently reverts to its previous on-disk
  version. The boot then runs the OLD script while every
  post-boot check on the file reports the old md5. Always `sync`
  before sysrq reboots.
- **Trap — `btmgmt public-addr` before first HCIDEVUP deadlocks**: the
  mgmt Set Public Address command waits for adapter setup, but setup
  only runs at the first `hciconfig up` — circular wait, the whole BT
  boot block stalls. Pin the bdaddr (if ever needed) only after the
  adapter is up and bluetoothd is running.
- **Trap — `hciconfig down`+`up` wedges the 4.4 hci_uart close path**:
  the next open times out (110) and only a reboot recovers. Same
  family as "never kill hciattach": the UART ldisc must be opened
  once and left alone.
- **Trap — the hciattach-qca holder can die silently right after
  attach** (seen on boot I): it prints "attached", daemonizes, then
  exits before the script's 3s check; the ldisc dies with it, hci0
  never registers, and the whole `[ -d hci0 ]` block is skipped. A
  dead holder frees the ldisc cleanly, so the script now re-attaches
  ONCE when hci0 is absent AND no hciattach-qca is running. Never
  apply this to a live holder (close wedges, see above).
- **Trap — manual dbus recovery on tmpfs /run**: `/var/run` is a
  symlink to `/run`, which the script mounts as a fresh tmpfs, so
  `dbus-daemon --system` after a manual recovery needs
  `mkdir -p /run/dbus` first, or it fails with
  `Failed to bind socket "/var/run/dbus/system_bus_socket": No such
  file or directory`.
- **Trap — musl-dynamic binaries silently break under another rootfs**:
  hciattach-qca had been built WITHOUT `-static` on Alpine (unlike
  fbdash), so under Ubuntu it failed to exec with ENOENT ("No such
  file or directory") because /lib/ld-musl-aarch64.so.1 does not exist
  there. The supervisor logged `setsid: failed to execute` and gave up
  cleanly. Fixed by rebuilding it glibc-static inside the Ubuntu
  chroot (gcc -O2 -static; 73 KB -> 711 KB). Anything copied between
  rootfs must be static or have its loader shipped.
- **Trap — dhclient deletes /etc/resolv.conf**: on the Ubuntu target,
  the isc-dhcp-client hook chain (which pokes systemd and ignores the
  chroot) left /etc/resolv.conf MISSING after the lease; ntpdate then
  died with "Temporary failure in name resolution" and apt hung on
  DNS. The bring-up watcher now rebuilds resolv.conf from the lease's
  domain-name-servers when no nameserver is present.
- **Trap — quote-concatenation into single-quoted -c strings**: baking
  parent values into a single-quoted setsid payload via
  `'"$VAR"'` made the PARENT's parse fragile (a later `${ns%%;*}` in
  the body flipped quote parity and broke sh -n at the wrong line).
  Pass such values via the ENVIRONMENT instead
  (`DHCP="$DHCP" NTP="$NTP" setsid /bin/sh -c '...'`) — setsid and sh
  preserve env, and the payload stays a pure single-quoted string.
- **Resolution — the supervisor**: after boot I (hciattach holder died
  silently right after attach) and boot J (the init subshell vanished
  right after a successful TLV download; chip proven fully initialized
  by a later manual attach that came up with the very bdaddr the log's
  NVM write had announced), the linear one-shot chain was replaced by
  a converging supervisor in wifi-bringup4.sh: every 10 s it takes the
  one idempotent step that moves the stack toward bluetoothd (init
  max x2 while none succeeded -> attach max x3 while no holder lives
  -> hciconfig up max x6 -> dbus + bluetoothd). Verified on cold boot
  K: wifi + NTP + hci0 UP RUNNING + bluetoothd + BLE scan, zero manual
  steps. One loose end never explained: boot J's init log ends with a
  third, truncated init run ("PF_ BUI" then EOF) no script path can
  have authored; the supervisor design tolerates exactly this class of
  ambiguity, which is the point.

## 2026-09-09 touch desktop (X/fbdev) + the fb0 readback deadlock

X desktop runs CPU-rendered on fbdev (no DRM/KMS, no GPU userspace on
the downstream 4.4 kernel): xserver-xorg-core + fbdev + openbox + tint2
+ xterm (WenQuanYi Micro Hei CJK) + matchbox-keyboard. Touch reaches X
through a STATIC InputDevice section + Option "AutoAddDevices" "no" —
with no systemd/udev on the box, modern Xorg discovers input ONLY via
udev, so without the static section xinput shows just the virtual core.

- **Trap — no-udev X input**: see above. Fix in tools/desktop/xorg.conf
  (touch0 = evdev on /dev/input/event4, GrabDevice, CorePointer).
- **Trap — matchbox-keyboard has no -g here**: the Ubuntu noble build
  exits with a usage error on `-g WxH+X+Y`. Dock it with an openbox
  <application> rule instead (tools/desktop/openbox-matchbox-keyboard.xml).
- **Trap — openbox <application name=> silently never matches**: this
  matchbox-keyboard (plain Xlib) does not set WM_CLASS to
  "matchbox-keyboard", so name=/class= matching missed and the keyboard
  stayed at smart-placement top. Match on the window TITLE instead
  (title="Keyboard" — read straight off its title bar). decor=no,
  layer=above, position force=yes 0/1450, size 1080x430 clears tint2.
- **Trap — obxprop / xprop availability**: xprop/xwininfo are NOT in the
  base image (x11-utils missing); obxprop with no argument is
  INTERACTIVE (waits for a click) and hangs an ssh heredoc. And any X
  query needs XAUTHORITY pointed at the live cookie
  (ps Xorg args -> -auth /tmp/serverauth.XXXX), else it returns empty
  with the error swallowed by 2>/dev/null.
- **Trap — repeated fb0 readback deadlocks mdss**: grabbing screenshots
  with `dd if=/dev/fb0` in a loop, racing fbdash's FBIOPAN_DISPLAY and
  Xorg's fbdev rendering, wedged the display pipeline: dsi_event_thread,
  msm_mpm_work_fn, Xorg (flush_work) and four dd's all stuck D-state in
  fb_open, load climbing past 9, screen frozen. D-state cannot be killed
  (SIGKILL is deferred until the syscall returns, which never happens);
  only a reboot clears it. Lesson: take fb0 screenshots SPARINGLY, one at
  a time, never overlapping a pan/commit; if one dd stalls do not fire
  more — each additional open queues on the same mdss lock. (Also: the
  `cnd` Qualcomm connectivity daemon left over in the base image pins a
  core at 100% — kill it; it serves no purpose outside Android.)


## 2026-09-10 Wi-Fi monitor mode: PROVEN (qcacld runtime con_mode) + the crash that followed

The WCN3990 qcacld-3.0 driver (v5.1.1.77V) is **built into** the kernel
(CONFIG_MODULES off — /proc/modules is empty, rmmod impossible), so the
classic Android recipe (rmmod wlan; modprobe wlan con_mode=N) does not
apply. Two dead ends first:

- nl80211: `iw phy` *advertises* monitor in supported iftypes and combos,
  but `iw dev wlan0 set type monitor` (and `interface add type monitor`)
  returns -22 — hdd's change_virtual_intf path rejects it.
- iwpriv: 202 vendor commands, but the only monitor-related one is
  `setMonChan` (channel/bandwidth for an already-monitor vdev).

The working path is the driver's built-in **runtime mode switcher**:
`/sys/module/wlan/parameters/con_mode` has a param setter
(`con_mode_handler` → `__con_mode_handler` in wlan_hdd_main.c) that stops
the WLAN modules, cleans up, and re-registers in the new mode — no reboot
needed. Enum (qdf_types.h): MISSION=0, MONITOR=4, FTM=5, EPPING=8.
Writing an invalid value (e.g. 2) fails -EINVAL but param_set_int has
already stored it — `cat` then lies; trust `iw dev` type instead.

Recipe (verified 2026-09-10): kill wpa_supplicant/dhclient, wlan0 down,
`echo 4 > con_mode`, ~4 s later wlan0 is `type monitor`; up it, set a
channel (`iw set channel 36` or `iwpriv wlan0 setMonChan 6 0` for 2.4G),
capture with a plain AF_PACKET socket (tools/wifi-mon/moncap.py) — frames
arrive radiotap-prefixed. Result: 318 frames/15 s on ch36 (beacon 145,
probe-rsp 84, data 12, deauth 1...), and ch6 works too. Monitor-mode
wakelock is taken by the driver automatically.

**The expensive lesson — switching back wedged the whole phone.**
`echo 0 > con_mode` returned EAGAIN ("Resource temporarily unavailable"):
con_mode_handler refuses while `cds_wait_for_external_threads_completion()`
sees external threads in the driver. Every retry EAGAIN'd, and a couple of
minutes later the kernel died entirely — USB gadget dropped off the bus
and the XBL crash handler came up as `QUSB__BULK` (19d2:ffae, Sahara
memory-debug mode, streams HELLO, refuses HELLO_RESP/RESET/DONE — only a
physical power-cycle recovers it). Open question: which thread kept the
driver busy (the AF_PACKET capture socket was already closed; candidates
are the rmnet/ipa unregister churn or a leftover nl80211 client). Until
the restore path is understood, treat monitor mode as a **one-way trip
per boot**: enter it only when you don't need STA Wi-Fi afterwards, and
reboot to get mission mode back. Reboot is safe — con_mode is a boot-time
default of 0, so Wi-Fi comes back normal on the next boot.

## 2026-09-10 LXDE session debugging — HOME=/, lxpolkit, lxpanel sizing

A boot-chain X session (rc.boot.ubuntu -> fbdash -> desktop.sh -> startx)
inherits the **kernel init environment: HOME=/**. startx then reads
//.xinitrc (not /root/.xinitrc) and the entire session runs with HOME=/,
which makes lxpanel/pcmanfm/openbox read //.config and fall back to
system defaults — visible symptom: a 224x26 panel sliver despite a
correct user config. Fix at TWO levels (belt and braces): export
HOME=/root in BOTH desktop.sh (before startx) and .xinitrc.

Other traps hit this session:

- **lxpolkit "No session for pid N" dialog**: lxpolkit (polkit agent) pops
  a modal error because there is no logind session. It is NOT (only) an
  xdg-autostart entry — lxsession launches it itself via
  `polkit/command=lxpolkit` in /etc/xdg/lxsession/LXDE/desktop.conf.
  Fix: `polkit/command=` (empty). Masking /etc/xdg/autostart alone is
  not enough.
- **`apt-get remove lxpolkit` cascades into removing lxsession** (and the
  lxde metapackage bits) — suddenly `startlxde` vanishes. Reinstall
  lxsession with --no-install-recommends; .xinitrc now execs
  `lxsession -s LXDE` directly and no longer depends on the startlxde
  wrapper at all.
- **libinput cannot replace evdev**: without udev it fails with
  "udev device never initialized" / "Invalid path /dev/input/event4".
  evdev attaches the synaptics as core pointer; the "[dix] touch0:
  unable to find touch point 0" spam is the XI2.2 MT path complaining
  but tap-as-click still works.
- **pkill -f "desktop.sh" over ssh kills your own remote shell** — the
  pattern matches the shell carrying the command. Break the string
  ("desk""top.sh") when pkilling session scripts.
- **xwd/xwininfo auth**: the Xorg `-auth /tmp/serverauth.*` file is not
  usable by clients; use XAUTHORITY=/root/.Xauthority (startx merges
  the cookie there) — and HOME must be /root or tools look in //.
- **lxpanel 0.10 config**: background=1 paints backgroundfile (an image),
  tintcolor alone gives a white panel. Base custom panels on the factory
  /etc/xdg/lxpanel/LXDE/panels/panel, not on memory.
- Rebooting the whole phone is cheaper than killing a duplicated
  session tree: lxsession auto-restarts its @-autostart children, so
  half-killed sessions keep respawning panels.

## 2026-09-11 qcacld-3.0 monitor-mode injection — mechanism research (Loukious port)

Goal: userspace raw 802.11 frame -> qcacld driver -> firmware -> RF TX,
verified by an independent sniffer.  Research on work/lineage-kernel
(cda6a278, qcacld v5.1.1.77V / wlan-cmn.driver.lnx.1.0 v5.1.1.2E):

- Why monitor RX-only by default: in QDF_GLOBAL_MONITOR_MODE the netdev
  gets `wlan_mon_drv_ops` (wlan_hdd_main.c) which has no ndo_start_xmit
  ("doesnot Tx").  nl80211 mgmt_tx is a dead end in monitor mode
  (__wlan_hdd_mgmt_tx needs a STA/SAP session; none exist in con_mode=4).
- The official reference: Loukious' QCACLD-3.0 injection patch shipped
  with Kali 2026.1 (github.com/Loukious/android_kernel_xiaomi_sm8150
  commit 8f0698bf92abef517980fe9a84615cd8bad16622, 13k lines with test
  scaffolding).  Core mechanism extracted and ported minimal (~450 lines):
  1. `wlan_mon_drv_ops.ndo_start_xmit = hdd_mon_tx` — strip radiotap,
     hand raw 802.11 to WMA.
  2. **Firmware rejects mgmt TX on MONITOR vdevs** (falls to beacon-only
     path -> DISCARD).  Injection requires a hidden **STA-type** helper
     vdev: VDEV_CREATE(STA) -> msleep(150) -> VDEV_START(monitor channel)
     -> msleep(150) -> PEER_CREATE(self, locally-administered MAC) ->
     msleep(100).  **No VDEV_UP** (STA vdev_up asserts without BSS peer).
     AP type would crash FW beacon TX offload (no beacon template).
  3. Submit with WMI_MGMT_TX_SEND_CMDID (send_mgmt_cmd_tlv) naming the
     helper vdev, chanfreq = monitor channel, desc from wmi_desc_get();
     completion handler wma_process_mgmt_tx_completion unmaps the nbuf
     and calls our tx_cmpl_cb which frees it.  If firmware never
     completes, the 50-entry desc pool self-limits and drops are counted.
  4. Helper vdev must be destroyed (PEER_DELETE -> VDEV_STOP ->
     VDEV_DELETE, 100 ms gaps) **before** the monitor vdev is torn down,
     else FW asserts in dispatch_wlan_pdev_cmds.  Hooked into __hdd_stop
     (monitor adapter) and hdd_stop_present_mode (con_mode switch).
- Our tree differences vs Loukious': sessionId (not vdev_id) on the hdd
  adapter, vdev_create_params uses if_id (not vdev_id), vdev_start_params
  has chan_freq/chan_mode (not channel.mhz/phy_mode), wma_txrx_node has
  addr/handle/is_vdev_valid (not objmgr .vdev pointer).  No
  `injection_ctx` per-adapter state — a single global suffices (one
  monitor vdev exists at a time).
- ndo_start_xmit runs in BH context (rcu_read_lock_bh): the WMI round
  trips + msleep are illegal there, so hdd_mon_tx only enqueues
  (kmalloc GFP_ATOMIC) and a system_wq work item does the WMI work.
- Buffer prep confirmed from send_mgmt_cmd_tlv: inline copy of the frame
  head (min(frm_len, mgmt_tx_dl_frm_len)) + DMA paddr of the nbuf;
  qdf_nbuf_alloc/qdf_nbuf_put_tail suffice (no cds_packet needed on the
  WMI path; cds_packet is only LIM's wrapper).
- Unverified on hardware yet: whether WCN3990 firmware sets
  WMI_SERVICE_MGMT_TX_WMI (near-certain for this gen; wmi_desc pool is
  only inited when the service bit is on — wmi_desc_get failing at
  runtime would be the symptom), and whether FW accepts a second vdev
  in global monitor mode.

## 2026-09-11 Production Ubuntu boot image REQUIRES the usb-diag config fragment

Symptom after flashing a CI kernel built WITHOUT a config fragment
(run 34578807184, lineageos_nx563j_defconfig only): device boots, usb0
pings, telnetd on :23 answers, but no sshd/fbdash — the initramfs mark
log (sde20 sectors 0-8) shows "boot target: ubuntu" then "rootfs rc.boot
done" immediately, i.e. rc.boot.ubuntu ran but its services died.

Root cause: the plain defconfig has **CONFIG_DEVTMPFS unset**, so the
initramfs falls back to tmpfs-/dev + mdev, and /dev/null ended up as a
**regular file** (140 KB of swallowed writes) instead of a char node.
sshd then dies at startup: `daemon() failed: No such device`
(/var/log/sshd.log on the ubuntu rootfs).  telnetd survives because it
only needs /dev/ptmx (which was a proper node).

Rule: any boot image carrying the production initramfs (Ubuntu/Alpine
boot target) must be built from a CI run with
`config_fragment=config/downstream-usb-diag.fragment`
(CONFIG_DEVTMPFS=y + gadget functions).  The bare-defconfig artifact is
only safe for the pure diag image, and even then /dev is fragile.

## 2026-09-11 Injection test round 1 (kernel 0009 v1) — silent TX path + mode-switch wedge

Setup: CI run 34590481624 (cda6a278 + patches 0001-0009 + usb-diag
fragment), boot image work/boot-ubuntu-inject2-signed.img (SHA256
cc073fb1...638763b9f).  Boot itself fully verified: Ubuntu userspace,
sshd, wlan0 STA back on 192.168.1.186 — daily driver intact.

Test: inject-test.sh ch36 — con_mode 0->4 OK, wlan0 type monitor,
`inject.py` reported sent 10/10 (55-byte radiotap+probe-req accepted by
hdd_mon_tx).  But **zero mon-inject dmesg lines**: qdf gates WMA_LOGI
per-module (g_qdf_trace_info bitmask, default hides INFO), so the
milestones were invisible; whether the hidden STA helper vdev was even
created is unknown from this round.  (Fix: milestones/drop-reasons
promoted to WMA_LOGE in 0009 v2, plus one-shot hdd mon-tx proof line.)

Then the **monitor->mission restore wedged the whole device**: first
`echo 0 > con_mode` returned EAGAIN (known Phase-3 issue), a retry ~60 s
later never connected — usb0 ping dead, Wi-Fi dead, no watchdog reset
within 4 min.  Correlation with the injection state (queued frames /
helper vdev vs. firmware) is plausible but unproven; the EAGAIN wedge
also existed before this patch.  Recovery: physical power cycle.

Lessons baked into v2: never rely on WMA_LOGI for critical-path
diagnostics on this driver (default trace mask hides it); always leave
rate-limited WMA_LOGE breadcrumbs at every drop branch.

## 2026-09-11 Why qcacld is completely silent in dmesg on this build

`dmesg | grep -c "wlan:"` = 0 — not a single qcacld line ever.  Cause:
qcacld Kbuild defines `-DWLAN_LOGGING_SOCK_SVC_ENABLE` (Kbuild:1327),
so `qdf_vtrace_msg()` routes every WMA/HDD/SME log (including
WMA_LOGE) to the userspace logging socket (cnss_diag on Android)
instead of printk.  The per-module qdf trace masks (default
FATAL|ERROR) are irrelevant — nothing reaches the kernel ring buffer.

For any downstream kernel debugging here: use raw `pr_err` /
`pr_err_ratelimited` in new code, or run a userspace logger on the
qdf logging socket.  The injection patch's diagnostics are now raw
printk (0009 v3).
