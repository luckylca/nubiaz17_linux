# Suggested MR title

Add Nubia Z17 (nx563j) LineageOS 22.2 / Android 15 support

# Suggested MR description

## Summary

This adds Kali NetHunter kernel support for the Nubia Z17 (`nx563j`) running LineageOS 22.2 / Android 15.

The submission contains:

- `devices.yml` metadata for `nx563j-los`
- prebuilt ARM64 `Image.gz-dtb`
- NetHunter USB/HID ramdisk additions
- an NX563J-specific AnyKernel patch for Magisk-patched system-as-root boot images

Kernel source:

`https://github.com/luckylca/android_kernel_nubia_msm8998_nethunter` (`nethunter-22.2`)

Kernel `Image.gz-dtb` SHA256:

`2038303df80404048427a24ea24b8f3b7909914dce8a38ba48cc8bc38d7986a4`

Declared features:

`[BT_RFCOMM, CDROM, HID-4, Injection, QCACLD, Internal_BT, NFS]`

## Real-device validation

Tested on a physical Nubia Z17 with LineageOS 22.2 / Android 15 and Kali NetHunter 2026.2.

- NetHunter kernel boots normally and Magisk root is retained.
- Kali full chroot runs successfully.
- Internal WCN3990 5 GHz monitor/injection works and cleanly returns to normal STA mode.
- `HID-4` keyboard/mouse configfs gadget support is verified against a macOS host.
- `CDROM` was verified through the same configfs gadget stack: `mass_storage.0/lun.0` was configured with `cdrom=1`, `ro=1`, and an ISO backing file; macOS enumerated the phone as `File-CD Gadget` (`0930:6545`).
- Boot-integrated USB Arsenal profiles were verified end-to-end:
  - `win,hid,adb` -> `046d:c317`, HID keyboard + mouse + ADB
  - `win,rndis,adb` -> `0525:a4a3`, `rndis0` created and `RNDIS_IPA NetDev was initialized`
  - `mac,reset` -> `2a70:f003`
  - `mac,reset,adb` -> `2a70:4ee7`, ADB restored
- Internal Bluetooth is functional.
- `BT_RFCOMM` was verified against a second physical Android device (Xiaomi MIX Flip): both devices bonded successfully, NX563J sent `NX563J_RFCOMM_TEST`, and the peer returned `MIXFLIP_ACK:NX563J_RFCOMM_TEST` (`CLIENT_PASS` / `SERVER_PASS`).
- BNEP/PAN was additionally validated as supporting evidence: both devices reached PAN connected state and exposed `bt-pan` as `UP,LOWER_UP`; TX/RX counters matched cross-direction traffic, and a temporary bound-interface IP test passed peer -> NX563J ICMP 3/3 with 0% loss.
- `NFS` client support was validated on real NX563J hardware against a macOS NFS server using a real mount and bidirectional file I/O; the submitted kernel contains NFS v3/v4 client support.
- Normal Wi-Fi STA operation remains functional after the injection changes.

## NX563J AnyKernel / SAR handling

The tested Android 15 setup uses a Magisk-patched system-as-root boot image. The device-specific `ak_patches/01-nx563j-magisk-sar-ramdisk.sh` keeps the NetHunter ramdisk additions when AnyKernel repacks that boot layout by installing the rc through Magisk `overlay.d` and exposing the HID descriptors through `${MAGISKTMP}`.

The submission validator checks this hook and simulates the resulting overlay layout. The resulting boot-integrated rc was also exercised on the real device by the USB Arsenal tests listed above.

## Known limitation

Internal WCN3990 injection is validated and recommended on 5 GHz. The 2.4 GHz injection path can trigger a Qualcomm firmware `ratectrl_11ac` assert, so this submission does not claim equal stability across both bands.

External USB Wi-Fi feature labels are intentionally not declared because the corresponding OTG adapters have not yet been hardware-tested.

## Validation against current upstream

Validated against current `kali-nethunter-kernels` `main`:

`e5991aa941188697e56c526c1dbc9979afa2db28`

- local submission validator: PASS
- merged `devices.yml` YAML parse: PASS, exactly one `nx563j` entry
- upstream `.yamllint.yml`: PASS
- upstream `bin/devices-integrity.py`: PASS (`271` directory kernel/version entries and `271` YAML kernel/version entries)
- current `kali-nethunter-installer` kernel-only build: PASS

Pre-MR installer package used for build-tool validation:

`kernel-nethunter-20260919_205420-nx563j-los-fifteen-pre-mr.zip`

SHA256:

`4f9b33dc87ca3080d0c30f4ebbc2ee9f37154fa009998b5742950de3f1400c23`
