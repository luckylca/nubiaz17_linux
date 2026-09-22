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

The account currently has no GitLab projects and therefore no fork of `kalilinux/nethunter/build-scripts/kali-nethunter-kernels`. Creating that fork is the remaining GitLab-side prerequisite before the branch can be pushed.

No commit email has been selected yet. The SSH public-key comment must not be treated as consent to publish that email permanently in upstream Git history. Prefer the GitLab private commit email if privacy is desired.

After the fork exists and a public/private commit email is selected, configure only the staging clone and create one focused signed-off commit, for example:

```bash
git config user.name '<public author name>'
git config user.email '<public commit email>'
git add devices.yml fifteen/nx563j-los
git commit -s -m 'Add Nubia Z17 LineageOS 22.2 support'
```

After that, push the single branch to the user's GitLab fork and open the merge request using `kali/MR_BODY.md` as the prepared description. Opening the official Kali MR remains an explicit user action/decision.
