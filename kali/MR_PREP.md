# NX563J NetHunter MR pre-submit checklist

Target upstream: `kalilinux/nethunter/build-scripts/kali-nethunter-kernels`.

## Candidate files

Merge `kali/devices.yml.nx563j` into upstream `devices.yml`, then add:

- `fifteen/nx563j-los/Image.gz-dtb`
- `fifteen/nx563j-los/ak_patches/01-nx563j-magisk-sar-ramdisk.sh`
- `fifteen/nx563j-los/ramdisk/init.nethunter.rc`
- `fifteen/nx563j-los/ramdisk/keyboard-descriptor.bin`
- `fifteen/nx563j-los/ramdisk/mouse-descriptor.bin`

Kernel SHA256:

`8f1652062fa052fff6d1f3fc2ddf9d1f1b9ed5fbd4afeec5157210bef44fe3a7`

Public source:

`https://github.com/luckylca/android_kernel_nubia_msm8998_nethunter` branch `nethunter-22.2`.

The submitted binary is the formal GitHub Actions artifact from source commit `a180aa33cd3d5603e4d1a89767940c2c94f01ec3` (`nx563j: promote validated Docker support`), CI run `35544472143`. That exact artifact was flashed and passed the full real-device Docker regression plus Magisk/Kali/Wi-Fi/Bluetooth/USB-configfs smoke checks.

## Automated pre-MR validation (2026-09-21)

- `./kali/validate_submission.sh`: PASS target is the final `[BT_RFCOMM, CDROM, Docker, HID-4, Injection, QCACLD, Internal_BT, NFS]` feature list, formal `a180aa33` kernel provenance/config, and reviewed USB/SAR fixes.
- Current GitLab upstream `main` was rechecked on 2026-09-21: remote HEAD `e5991aa941188697e56c526c1dbc9979afa2db28`, still identical to the staging base.
- Candidate entry appended to that full upstream `devices.yml`: YAML parse PASS with exactly one `nx563j` entry.
- Current upstream `.yamllint.yml` against the merged full `devices.yml`: PASS.
- Current upstream `bin/devices-integrity.py` against an exact Git-tree directory skeleton: PASS (`Kernels in directories: 271`, `Kernels in YAML kernels: 271`). This metadata-only skeleton is valid because the official integrity script checks directory presence/IDs rather than kernel file contents.
- Current upstream `kali-nethunter-installer` main at `e63b0476a7fd5767729208c68a78ad79afaaf556`: kernel-only `--installer` build PASS.
- Generated final Docker pre-MR package: `artifacts/kali/kernel-nethunter-20260921_0756-nx563j-los-fifteen-pre-mr-docker.zip`.
- Pre-MR package SHA256: `4b0de9214e84aa1b2bec5119bd6e9d3d69a315b0a4d66b4120461f1841d23f02`.
- The package embeds the formal `a180aa33` candidate `Image.gz-dtb`, keyboard descriptor, mouse descriptor, and SAR patch byte-for-byte. The rc matches after trailing-whitespace / EOF-blank-line normalization, and the validator rejects any functional rc change.

The formal `a180aa33` kernel artifact is now the hardware-tested submission baseline. The older 2026-09-16/19 packages remain useful only as historical ramdisk/HID validation anchors.

## Already verified on real NX563J hardware

- LineageOS 22.2 / Android 15 boots with the NetHunter kernel.
- Kali 2026.2 full chroot works.
- NetHunter app / terminal / KeX packages install and run.
- Internal WCN3990 5 GHz monitor/injection: channel 36, 20/20 probe-request injection, no firmware assert, clean return to STA.
- USB HID keyboard gadget enumerated on a Mac host and delivered repeated test keystrokes in the 2026-09-17 hardware baseline. Because NX563J uses a 4.4 configfs gadget stack, the official feature label is `HID-4`, not legacy 3.x `HID`.
- Internal Bluetooth adapter enables correctly; 2026-09-19 framework recheck shows `enabled: true`, `state: ON`, `name: Nubia Z17`, and RFCOMM/L2CAP listening state in dumpsys.
- Normal Wi-Fi STA remains functional after the injection changes.
- RNDIS/GSI configfs function exists on the verified kernel.
- Kali chroot recovery was rechecked on 2026-09-19 after switching back from Ubuntu: Magisk root works, the NetHunter busybox relative-link fix was restored, `/sdcard/nh_files` was restored, and Kali 2026.2 tools `python3`, `aircrack-ng`, `bettercap`, `wifite`, and `reaver` run inside the chroot.
- The ramdisk template's duplicated `win,reset*` triggers in the Mac section were corrected to `mac,reset*`; the validator only permits these three reviewed executable-line changes relative to the tested ZIP.
- 2026-09-20 USB Arsenal end-to-end regression PASS on the boot-integrated candidate rc: `win,hid,adb` enumerated on macOS as `046d:c317` with `hid.0 + hid.1 + ffs.adb`; `win,rndis,adb` enumerated as `0525:a4a3`, created `rndis0`, and logged `RNDIS_IPA NetDev was initialized`; corrected `mac,reset` enumerated as `2a70:f003`; corrected `mac,reset,adb` enumerated as `2a70:4ee7` with ADB restored.
- 2026-09-20 `CDROM` PASS: the live configfs `mass_storage.0/lun.0` was configured with `cdrom=1`, `ro=1`, and an ISO backing file; macOS enumerated NX563J as `File-CD Gadget` with VID/PID `0930:6545` and BSD device `disk4`.
- 2026-09-20 `BT_RFCOMM` end-to-end PASS against a rooted Xiaomi MIX Flip peer: both devices auto-bonded to `BOND_STATE_BONDED`; NX563J sent `NX563J_RFCOMM_TEST`, the peer received it and returned `MIXFLIP_ACK:NX563J_RFCOMM_TEST`, with `CLIENT_PASS` / `SERVER_PASS` on the two ends.
- BNEP/PAN was also verified as extra evidence (there is no separate upstream BNEP feature label): both peers reached `BluetoothPan` connected state, both exposed `bt-pan` as `UP,LOWER_UP`, link counters matched cross-direction byte-for-byte, and a temporary bound-interface IP test produced successful MIX→NX ICMP `3/3` with 0% loss. Reverse ICMP was filtered by Android tether/firewall policy, not by the BNEP link.
- `NFS` client support was hardware-verified on NX563J against a macOS NFS server with a real mount plus bidirectional file I/O; the current NetHunter kernel also contains `CONFIG_NFS_FS=y`, `CONFIG_NFS_V3=y`, and `CONFIG_NFS_V4=y`.
- `Docker` PASS on the exact formal CI artifact submitted here (`a180aa33`, Image SHA256 `8f165206…e3a7`): Docker 29.1.3/containerd 1.7.35 completed runtime, mqueue, exec, bind, cgroups, bridge/private-netns publishing, slirp uplink/hostfwd, public IPv4, DNS, domain HTTP, Android-firewall isolation, and cleanup tests.

## Intentionally not claimed in devices.yml

- External Wi-Fi feature labels such as `RTL88XXAU`: do not claim without OTG adapter hardware testing, even where kernel-side support exists.
- `CAN`, `ATH9K_HTC`, `RTL8XXXU`: enabled in the kernel does not equal hardware validation; keep them out of the official feature list for now.

Current declared features remain deliberately conservative but aligned with the current upstream README feature names:

`[BT_RFCOMM, CDROM, Docker, HID-4, Injection, QCACLD, Internal_BT, NFS]`

## Known limitation to disclose

Internal WCN3990 injection is verified on 5 GHz. A 2.4 GHz path can trigger a Qualcomm firmware `ratectrl_11ac` assert, so the initial MR should describe internal injection as tested/recommended on 5 GHz rather than implying all bands are equally stable.

## Before opening the MR

1. Run `./kali/validate_submission.sh` and require PASS.
2. Restore the tested Kali state only when a destructive device switch is acceptable.
3. Keep the 2026-09-20 USB Arsenal regression evidence with the MR notes; the boot-integrated candidate rc has passed HID+ADB, RNDIS+ADB, `mac,reset`, and `mac,reset,adb` on real hardware.
4. Keep `BT_RFCOMM` declared: the 2026-09-20 rooted Android peer test passed bonding plus bidirectional RFCOMM payload/ACK; BNEP/PAN also passed at link/data level as supporting evidence.
5. Rebase/copy the candidate onto the latest upstream `main`, run upstream lint/pipeline, then open the MR.

## Separate upstream issue

The Android 15 + Magisk NetHunter module BusyBox problem was kept out of the NX563J kernel MR and submitted separately to `kali-nethunter-installer` as MR `!45` (`Fix BusyBox symlinks for module overlays`). The fix changes the module's `busybox_nh` and `busybox` aliases to relative symlinks in both `nethunter/post-fs-data.sh` and `common/tools/install-busybox.sh`. This matches the relative-link handling already used by the KernelSU path in `customize.sh` and the layout verified on the NX563J.
