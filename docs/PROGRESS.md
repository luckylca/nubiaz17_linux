# Progress

Last updated: 2026-09-07

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

The Mac has a working Android platform-tools install:

`/Users/lucky/Library/Android/sdk/platform-tools/adb`

but the phone is currently not enumerating as an Android/Qualcomm USB device:

- `adb devices -l`: no device
- `fastboot devices -l`: no device
- macOS USB inventory: no Nubia / NX563J / Android / Qualcomm match

This is below the ADB authorization layer; the USB device itself is not presently visible to macOS.

## Next device-side actions

Once USB enumeration appears:

1. run `scripts/device_probe.sh`;
2. record serial/model/build/bootloader state;
3. dump the exact by-name partition map;
4. identify boot/recovery/system/vendor/userdata layout;
5. capture original boot and recovery images where permissions allow;
6. hash all captured images;
7. determine whether temporary `fastboot boot` is accepted.

## Next software actions

- Make downstream CI compile `Image.gz-dtb` reproducibly.
- Make mainline-oriented CI compile the existing NX563J DTS branch.
- Add boot image unpack/repack tooling after an original boot image is captured.
- Add rootfs generation only after storage/boot strategy is fixed from the real device.
