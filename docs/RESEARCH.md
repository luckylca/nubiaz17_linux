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
