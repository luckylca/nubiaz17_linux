# NX563J Kali NetHunter upstream submission status

Last refreshed: 2026-09-22.

## Upstream bases

- `kali-nethunter-kernels` main: `e5991aa941188697e56c526c1dbc9979afa2db28`
- `kali-nethunter-installer` main: `e63b0476a7fd5767729208c68a78ad79afaaf556`
- public kernel source branch `nethunter-22.2`: `a180aa33cd3d5603e4d1a89767940c2c94f01ec3`
- formal submitted `Image.gz-dtb` SHA256: `8f1652062fa052fff6d1f3fc2ddf9d1f1b9ed5fbd4afeec5157210bef44fe3a7`

## Exact upstream payload

The MR should contain only the existing `devices.yml` modification plus these five new files:

- `fifteen/nx563j-los/Image.gz-dtb`
- `fifteen/nx563j-los/ak_patches/01-nx563j-magisk-sar-ramdisk.sh`
- `fifteen/nx563j-los/ramdisk/init.nethunter.rc`
- `fifteen/nx563j-los/ramdisk/keyboard-descriptor.bin`
- `fifteen/nx563j-los/ramdisk/mouse-descriptor.bin`

Do not submit project-local docs, test harnesses, boot images, generated installer ZIPs, Docker binaries, logs, or archived CI metadata to the Kali kernel repository.

## Declared features

`[BT_RFCOMM, CDROM, Docker, HID-4, Injection, QCACLD, Internal_BT, NFS]`

External Wi-Fi, CAN, USB serial, SDR, and other future/hardware-dependent capabilities remain intentionally undeclared.

## 2026-09-22 validation

Fresh staging tree:

`/tmp/nx563j-kali-nethunter-kernels-mr-final-20260922`

The staging base and live upstream main were both exactly:

`e5991aa941188697e56c526c1dbc9979afa2db28`

Validation results:

- `STRICT_REMOTE=1 bash kali/validate_submission.sh`: PASS
- merged `devices.yml` YAML parse: PASS
- upstream `yamllint devices.yml`: PASS
- upstream `bin/devices-integrity.py`: PASS (`271` directories / `271` YAML entries)
- formal CI kernel provenance/config verification: PASS
- Docker-required Kconfig verification: PASS
- `CONFIG_USB_DUMMY_HCD` disabled: PASS
- current Docker pre-MR package versus candidate kernel/ramdisk/HID/SAR assets: PASS
- public kernel source branch reachability: PASS
- current installer main is unchanged from the already successful kernel-only build at `e63b0476...`

A read-only phone check on 2026-09-22 also confirmed the connected NX563J is booted, Magisk root works, Docker-critical runtime Kconfig options remain enabled, and `CONFIG_USB_DUMMY_HCD` remains disabled. The first 16,717,096 bytes of the live boot partition match `work/formal-docker-a180aa33/boot-nethunter-formal-a180aa33.img` byte-for-byte by SHA256 (`dce6db0c276440f338122d8e5019e6b3a5c42dff99aea6c99da34ae9efbd9970`), proving the phone is still running the exact formal promotion boot used for validation. The full 64 MiB partition hash is not expected to equal the smaller image-file hash because bytes beyond the image length are outside that comparison. No destructive phone operation was performed during this refresh.

## GitLab submission identity

GitLab SSH authentication is now working for account `@luckyyyyyy` (public profile name `CHENGAN LU`). The local `~/.ssh/id_ed25519` public key is registered with GitLab. Because this network closes GitLab SSH port 22, `~/.ssh/config` routes only `gitlab.com` through GitLab's official `altssh.gitlab.com:443` endpoint; the scanned ED25519 host key was verified against GitLab's published fingerprint before it was added to `known_hosts`.

The fork now exists as `luckyyyyyy/kali-nethunter-kernels` (GitLab project ID `86737021`) and correctly reports `kalilinux/nethunter/build-scripts/kali-nethunter-kernels` as its parent. Its `main` branch matches upstream exactly at `e5991aa941188697e56c526c1dbc9979afa2db28`.

A single focused upstream commit was created in the fresh staging clone using the GitLab private noreply identity `CHENGAN LU <42606990-luckyyyyyy@users.noreply.gitlab.com>` and `git commit -s`:

- commit: `e9c5e673e6c4bd7905bfc05bfbc465723e9af8b8`
- title: `Add Nubia Z17 LineageOS 22.2 support`
- delta from upstream `main`: exactly one commit
- changed paths: exactly six (the `devices.yml` edit plus the five `fifteen/nx563j-los` files listed above)
- `Signed-off-by` uses the same GitLab private noreply identity; the user's real mailbox is not present in the commit

The branch `nx563j-los` has been pushed to the fork and verified byte-for-byte by commit ID: local and remote both resolve to `e9c5e673e6c4bd7905bfc05bfbc465723e9af8b8`. GitLab's repository compare API reports exactly one commit and six diffs.

The official Kali merge request was opened on 2026-09-22 as `kalilinux/nethunter/build-scripts/kali-nethunter-kernels!465` with title `Add Nubia Z17 (nx563j) LineageOS 22.2 / Android 15 support`. GitLab reports the MR as `opened`, non-draft, and `mergeable` / `can_be_merged`, targeting upstream `main` from fork branch `luckyyyyyy:kali-nethunter-kernels/nx563j-los` at commit `e9c5e673e6c4bd7905bfc05bfbc465723e9af8b8`.

The MR-triggered GitLab pipeline `2869953778` completed successfully. Both required lint jobs passed: `yamllint=success` and `devices_integrity=success`. The submission is now awaiting Kali maintainer review/merge rather than any further technical preparation.
