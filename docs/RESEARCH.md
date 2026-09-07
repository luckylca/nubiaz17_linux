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
