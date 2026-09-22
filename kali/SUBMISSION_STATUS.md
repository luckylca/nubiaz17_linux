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

A read-only phone check on 2026-09-22 also confirmed the connected NX563J is booted, Magisk root works, Docker-critical runtime Kconfig options remain enabled, and `CONFIG_USB_DUMMY_HCD` remains disabled. No destructive phone operation was performed during this refresh.

## Submission identity blocker

Technical submission data is complete. This Mac currently has no global Git author name/email, no authenticated `glab`, and no working GitLab SSH identity. Do not invent an author identity or expose a private email.

Before creating the upstream commit, choose the public author identity to be permanently recorded in Git history, preferably a GitLab noreply address if privacy is desired. Then configure the staging clone locally and create one focused signed-off commit, for example:

```bash
git config user.name '<public author name>'
git config user.email '<public commit email>'
git add devices.yml fifteen/nx563j-los
git commit -s -m 'Add Nubia Z17 LineageOS 22.2 support'
```

After that, push the single branch to the user's GitLab fork and open the merge request using `kali/MR_BODY.md` as the prepared description. Opening the official Kali MR remains an explicit user action/decision.
