# Progress

Last updated: 2026-09-09

## 2026-09-09 Ubuntu 24.04 as a selectable boot target

The end goal is a full Debian/Ubuntu userland with display, touch and
Wi-Fi. Milestone reached: the userdata filesystem now carries an
official **Ubuntu Base 24.04.4 arm64** rootfs at `/ubuntu` (SHA-256
verified against Canonical's SHA256SUMS), and the initramfs `init`
selects the chroot target via `/boot-target` (`ubuntu` -> /ubuntu with
`rc.boot.ubuntu`; anything else -> the Alpine mini-rootfs, so a broken
experiment can never wedge the boot).

Validated in stages:

1. **chroot validation from Alpine**: apt over HTTPS (aliyun
   ubuntu-ports mirror; noble = deb822 `ubuntu.sources`; the 4.4 kernel
   breaks apt's `_apt` sandbox DNS, so `APT::Sandbox::User "root"`),
   openssh-server answering SSH from the Mac with wlan0/hci0 visible.
2. **Boot L (first Ubuntu-target cold boot)**: Ubuntu userspace booted,
   sshd + fbdash + dhclient Wi-Fi all worked; NTP and BT failed and
   were root-caused (dhclient hooks deleted /etc/resolv.conf; the
   hciattach-qca copy was musl-dynamic, ENOENT under Ubuntu). The BT
   supervisor logged the failure precisely (`setsid: failed to
   execute`) and gave up cleanly — the resilience design paid off.
3. **Fixes**: watcher rebuilds resolv.conf from the lease;
   hciattach-qca rebuilt glibc-static in the chroot; live recovery then
   brought hci0 UP RUNNING + bluetoothd (BlueZ 5.72) under Ubuntu.
4. **Boot M (verified unattended)**: cold boot into the Ubuntu target
   reached `wifi=YES, NTP year=2026, hci0 UP RUNNING
   (00:A0:C6:A6:F3:E7), bluetoothd (BlueZ 5.72), fbdash on panel` with
   zero manual steps; BLE scan found 11 devices. **Ubuntu 24.04 is now
   the daily-driver userland.** Rollback = delete `/boot-target` (or
   its `ubuntu` line) and reboot; the Alpine mini-rootfs is untouched
   at `/`.

No systemd (kernel 4.4 has no cgroup v2); services are hand-started by
`initramfs/rc.boot.ubuntu` + the rootfs-agnostic `wifi-bringup4.sh`
(dhclient/udhcpc, ntpdate/ntpd, bluetoothd path shims).

Touch: `nubia_synaptics_dsx` (i2c 5-0020) registers as
**/dev/input/event4** (standard evdev MT, `ABS_MT_*` + `BTN_TOUCH`),
IC confirmed alive after resume retries. **Verified live 2026-09-09**:
a physical swipe produced IRQ 125 bursts and a clean MT protocol B
event stream (`ABS_MT_TRACKING_ID` -> `BTN_TOUCH` down -> X=429,
Y=401, in range for 1080x1920). No kernel work needed; userspace reads
evdev directly. **All six priority hardware items are now working
under Ubuntu: UFS, SSH, display, touch, Wi-Fi, Bluetooth.**

## Current authoritative status (pre-Ubuntu baseline)

> **Current authoritative status:** the live inventory, backups, both kernel CI paths, and signed boot repacking are already complete. The "Current blocker" and "Next actions" sections below reflect the remaining device-side work.

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
3. Replace the fbtest color-band holder with a real status dashboard (fb text rendering: IP, uptime, SSH state), then bring up touch (Synaptics RMI4 — driver probes but logged spontaneous resets + I2C errors during panel suspend; retest while display is alive).

## Next software actions

- Migrate the boot flow from busybox-PID1+chroot toward switch_root into the Alpine rootfs with OpenRC service management.
- Set the device clock (NTP) so HTTPS apk repos validate; keep aliyun mirror as the default repo source.
- Investigate display bring-up (JDI R63452 panel via downstream mdss, or simple-framebuffer) and Synaptics RMI4 touch.
- Continue the long-term migration of NX563J-specific DTS/drivers from the 6.0-oriented bridge toward newer generic MSM8998 mainline.


## 2026-09-09 Bluetooth UNATTENDED: cold boot to powered controller

Cold boot now reaches a fully working Bluetooth stack with zero manual
steps: Wi-Fi autostart (wlan0 associated, DHCP lease), `hci_qcomm_init`
userspace TLV download (45 s settle + retry), `hciattach-qca` N_HCI/QCA
ldisc, `hciconfig up` -> UP RUNNING, dbus + bluetoothd (BlueZ 5.76)
powered, BLE scan live (70+ device events in 10 s).

Two more kernel bugs stood between the manual proof and this
(RESEARCH.md parts 3-4):

- `patches/downstream/0007` (final form): `qca_setup` keeps the baud
  dance (hci_qcomm_init leaves the chip at 115200; it follows the VS
  set-baud to 3M), skips the kernel EDL rome download (the
  userspace-initialized chip answers its version request 0x0c ->
  EBUSY), and leaves IBS OFF (with IBS on, every post-setup frame
  parks in tx_wait_q waiting for a WAKE_ACK that never comes ->
  ETIMEDOUT).
- `patches/downstream/0008`: the userspace NVM sometimes leaves
  LE_Host_Supported already set (chip-reset lottery, same one that
  randomizes the bdaddr tail); the chip then answers the kernel's
  redundant write 0x0c -> EBUSY -> open aborts. The init request now
  tolerates Command Disallowed for that command.

Also: `/run` is now a tmpfs in the bring-up script (a stale
`/run/dbus/dbus.pid` from the persistent rootfs silently killed
bluetoothd autostart on one boot).

**Boot K (2026-09-09), fully verified unattended**: after two
consecutive boots lost the chain to silent deaths in the orchestration
(boot I: the hciattach holder died right after attach; boot J: the
init subshell vanished right after a successful TLV download - no
error logged, no OOM, chip fully initialized underneath), the one-shot
linear chain was replaced by a converging supervisor (every 10 s, take
the one idempotent step toward bluetoothd: init x2 max -> attach x3
max -> hciconfig up x6 max -> dbus + bluetoothd; never kills or cycles
anything). Cold boot K: wifi=YES, NTP year=2026, hci0 UP RUNNING
(00:A0:C6:7B:C0:E3), bluetoothd up, BLE scan 11 devices - zero manual
steps.

## 2026-09-09 Bluetooth COMPLETE: kernel hci0 up, BlueZ 5.76 scanning

The BT kernel (CI run `34294947043`, fragment
`config/downstream-usb-diag-bt.fragment`) is flashed to `boot` and
verified live:

- `/root/hciattach-qca /dev/ttyHS0 3000000` (N_HCI ldisc + QCA proto)
  after `hci_qcomm_init -e -N` → kernel registers `hci0`.
- `hciconfig hci0 up` → UP RUNNING, BD Address `00:A0:C6:A3:43:4F`,
  zero HCI errors.
- dbus + bluetoothd (BlueZ 5.76, aliyun mirror): controller powered,
  alias `nx563j-linux`, BLE scan discovers 9+ real devices with RSSI.
- Wi-Fi unaffected: wlan0 autostart still associates and gets a lease.
- Four latent never-compiled-before bugs fixed to get here, all
  documented in `docs/RESEARCH.md` 2026-09-09 Bluetooth part 2:
  `hci_ldisc` stale rx_lock (patch 0005), `btqca` always-true array
  checks (patch 0006), the fragment's legacy-gadget choice conflict
  that silently revoked `USB_CONFIGFS_UEVENT`, and the
  multi-composite `rndis.o`/`KBUILD_MODNAME` failure (RNDIS dropped;
  USB networking uses NCM).
- Bring-up script updated: hci_qcomm_init retry loop (the instant-wlan0
  fire raced the BT block out of reset), hciattach + `hciconfig up` +
  bluetoothd autostart, udhcpc lease verification.

## 2026-09-09 Bluetooth: chip alive, TLV download + MAC proven; kernel fragment ready

**The WCN3990 BT block answers on `/dev/ttyHS0`: `hci_qcomm_init` completes the TLV rampatch+NVM download from the `bluetooth` partition (sde22), switches to 3M baud and reads the chip MAC `00:a0:c6:c3:c9:3a`.**

Root cause of the initial total UART silence (all six rails, clock, pinctrl and UART-DM loopback verified stock-identical against the decompiled stock DTB): **the BT block inside the WCN3990 package is only released at chip POR when the BT rails are already on.** Our chip POR'd with the modem boot while the btpower rfkill was still blocked. Fix: unblock rfkill0 before the modem boots (now in `wifi-bringup4.sh` step 5b), then the init succeeds on the first try.

Also established: the stock Nubia kernel ships `CONFIG_BT_HCIUART` unset — stock Android talks HCI through the `wcnss_filter` userspace daemon instead. For BlueZ we want kernel `hci0`, so `config/downstream-bt.fragment` adds `CONFIG_BT_HCIUART(+H4,+QCA)` + RFCOMM/BNEP/HIDP. Remaining: CI kernel rebuild with that fragment, then `hciattach` → `hci0`.

## 2026-09-09 Wi-Fi works: wlan0 up, associated, internet verified

**WCN3990 is fully up under Linux and online: `wlan0`/`wlan1`/`p2p0` created by qcacld v5.1.1.77V, scan finds 11 networks on both bands, association to the user's 5 GHz WPA2 AP succeeds, DHCP lease `192.168.1.186/24` from `192.168.1.1`, gateway/DNS/internet ping all 0% loss, HTTP download verified (busybox wget https needs a cert bundle — rootfs detail, not Wi-Fi).** wpa_supplicant config persists in the rootfs (`update_config=1`, network entry saved via wpa_cli; credentials intentionally not committed to git).

The bring-up recipe is `tools/wifi-bringup/wifi-bringup4.sh` (proven end-to-end on three consecutive modem cycles). The chain: perms fix → mounts incl. persist → firmware staging in both fs roots → irsc → IPA uC load → QMI daemons with working RFS → modem boot → QMI_IPA_INIT → `wlan_pd` servreg indication → `WLAN FW is ready` → qcacld probe → wlan0.

Four root causes were fixed this session (details in `docs/RESEARCH.md`):

1. **pd-mapper crash-loop**: mdev leaves `/dev/null`/`/dev/urandom` 0660 root:root (and `/dev/null` was once a 35-byte regular file); pd-mapper runs as uid 1000 → fix perms before any daemon.
2. **No QMI_IPA_INIT without the IPA uC** (v3 "no uC like stock" experiment disproven): on MSM8998/GSI, `ipa3_post_init` is deferred until `ipa_fws` loads via a `/dev/ipa` write; only then does rmnet register its QMI service and send `QMI_IPA_INIT_MODEM_DRIVER_REQ` when the modem's IPA_Q6 (0x31) service arrives.
3. **The wlan_pd gate — tftp RFS**: the modem boots fine and answers QMI_IPA_INIT, but never starts `wlan_pd` unless its RFS write check (`/vendor/rfs/msm/mpss/readwrite/server_check.txt`, a symlink into `/mnt/vendor/persist/rfs/...`) succeeds. Mounting persist (`/dev/sda2`, RW) before `tftp_server` starts unblocked it: `Indication received from msm/modem/wlan_pd, state: 0x1fffffff` (stock-identical), `icnss: QMI Server Connected: state: 0x981`.
4. **qcacld ini hang**: `hdd_parse_config_ini`'s `request_firmware("wlan/qca_cld/WCNSS_qcom_cfg.ini")` runs on a kernel workqueue whose fs root is the **initramfs**, not the chroot — the file must exist under `/proc/1/root/fwimage/` too, or the request falls into the unanswered usermode-helper, hangs 120 s+, and the FW watchdog fails the probe (-22).

Supporting tooling: `tools/logcatd/logcatd.c` (fake logd: binds `/dev/socket/logdw`, dumps bionic liblog to `/var/log/logcatd.log`). Modem bounce without reboot: `kill -9` the holder of `/dev/subsys_modem` (pm-service); its keepalive re-boots the modem and the whole wlan chain re-runs.

Remaining for Wi-Fi: nothing hardware-side. Rootfs polish: TLS cert bundle for wget/https, `iw` package, auto-associate service from rc.boot.

## 2026-09-08 touch fixed: full multi-touch events on nubia_synaptics_dsx

**Touch is working — user touch produced a live stream of MT events (982 log lines: tracking IDs, BTN_TOUCH, X/Y, pressure) on `/dev/input/event4`.**

The root cause was three stacked bugs, fixed by three patches (all in `patches/downstream/`, details in `docs/RESEARCH.md`):

1. **IC settling window** (~15-20 s after boot): `0002-touch-resume-delay-until-ic-ready.patch` defers the driver's resume until t=20 s.
2. **Recovery cascade**: the driver's `tp_recovery` path GPIO-resets the IC on transient NAKs, each reset restarting the settling window: `0003-disable-tp-recovery-reset-cascade.patch` forces `tp_recovery_enable = false`.
3. **Empty fn-handler list + razor-thin retry window**: resume's `reset_device` empties the function-handler list, then the re-query races the still-settling IC and loses within `SYN_I2C_RETRY_TIMES=3` (~60 ms): `0004-widen-i2c-retry-window.patch` widens it to 10 (~200 ms), and `0002` rebuilds the fn list if a resume still ends up empty.

Verified on `nx563j-diag-touch5-signed.img` (all four patches): `resume workqueue finish (IC alive)` on **attempt 1** at t=20.5 s (3 I2C retries, no fn-list rebuilds), then real user touches produce proper MT-B event streams. New on-device tool `tools/touchdump/` (errno-reporting evdev reader) used for capture.

## 2026-09-08 touch root cause found, fix building in CI

- Symptom: touch IC (in-cell Synaptics RMI4) probes OK at ~1.5 s, then NAKs all I2C from ~1.9 s forever (all rails verified on, all addresses dead).
- Root cause (proven against stock Android early dmesg): the IC needs a settling window after boot. Stock's first touch I2C is at ~17-18 s and succeeds; our kernel's fb unblank pokes it at ~1.9 s and the driver's reset loop then keeps it dead. A late first contact (t=1312 s on an earlier boot) succeeds — so the fix is timing, not power or firmware.
- `patches/downstream/0002-touch-resume-delay-until-ic-ready.patch` (defer resume to 20 s, verify IC, rail-cycle retry) is building in CI now (push-triggered, artifact tagged `-patches`).
- Full analysis + newly discovered operational hazards (debugfs/gpio hangs, unbind deadlock, sysrq-b recovery) in `docs/RESEARCH.md`.

## 2026-09-08 display works: Linux draws on the JDI R63452 panel

**The screen shows Linux-drawn content (red/green/blue/white bands) at boot — user-confirmed.**

- Working recipe: hold `/dev/fb0` open (else mdss re-suspends in ~1 s) → unblank → mmap + draw + `FBIOPAN_DISPLAY` (the `write()` path is broken, ENODEV) → light the backlight (`lcd-backlight` + `wled`) → enable `msm_cmd_autorefresh_en`. Full analysis in `docs/RESEARCH.md`.
- `tools/fbtest/fbtest.c` (built on-device with the newly installed gcc 13.2.1 toolchain, installed via offline apk) runs at boot as `fbtest 999999` from `/root/rc.boot` — doubling as a boot-success splash and the fb holder that keeps the panel alive.
- On-device aarch64 toolchain: gcc 13.2.1 + binutils + make + musl-dev + linux-headers, installed offline from pinned Alpine v3.20 apks (dependency closure resolved on the Mac, 16+1 packages).
- Key insight: `panel_status=alive` ≠ panel lit — the frame was reaching the panel from the first fbtest run; the backlight was simply off (WLED defaults to 0 and the panel power-on sequence never re-runs after the splash handoff).

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
