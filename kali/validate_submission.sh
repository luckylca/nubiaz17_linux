#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KALI="$ROOT/kali"
CANDIDATE="$KALI/fifteen/nx563j-los"
SAR_PATCH="$CANDIDATE/ak_patches/01-nx563j-magisk-sar-ramdisk.sh"
ARTIFACT_DIR="$ROOT/artifacts/kali/nethunter-kernel-a180aa33"
ARTIFACT="$ARTIFACT_DIR/Image.gz-dtb"
ARTIFACT_CONFIG="$ARTIFACT_DIR/kernel.config"
ARTIFACT_SOURCE="$ARTIFACT_DIR/KERNEL_SOURCE_COMMIT"
BASELINE_KERNEL_ZIP="$ROOT/artifacts/kali/kernel-nethunter-20260916_115945-nx563j-los-fifteen.zip"
PREMR_ZIP="$ROOT/artifacts/kali/kernel-nethunter-20260921_0756-nx563j-los-fifteen-pre-mr-docker.zip"
EXPECTED_KERNEL_SHA="8f1652062fa052fff6d1f3fc2ddf9d1f1b9ed5fbd4afeec5157210bef44fe3a7"
BASELINE_KERNEL_SHA="2038303df80404048427a24ea24b8f3b7909914dce8a38ba48cc8bc38d7986a4"
FORMAL_SOURCE_COMMIT="a180aa33cd3d5603e4d1a89767940c2c94f01ec3"
SOURCE_REPO="https://github.com/luckylca/android_kernel_nubia_msm8998_nethunter.git"
SOURCE_BRANCH="nethunter-22.2"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'
  fi
}

fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[ OK ] $*"; }

for f in \
  "$KALI/devices.yml.nx563j" \
  "$CANDIDATE/Image.gz-dtb" \
  "$CANDIDATE/ramdisk/init.nethunter.rc" \
  "$CANDIDATE/ramdisk/keyboard-descriptor.bin" \
  "$CANDIDATE/ramdisk/mouse-descriptor.bin" \
  "$SAR_PATCH" \
  "$ARTIFACT" \
  "$ARTIFACT_CONFIG" \
  "$ARTIFACT_SOURCE" \
  "$BASELINE_KERNEL_ZIP" \
  "$PREMR_ZIP"; do
  [[ -f "$f" ]] || fail "missing: ${f#$ROOT/}"
done
pass "candidate file set complete"

kernel_sha="$(sha256_file "$CANDIDATE/Image.gz-dtb")"
[[ "$kernel_sha" == "$EXPECTED_KERNEL_SHA" ]] || fail "candidate kernel sha256 mismatch: $kernel_sha"
[[ "$(sha256_file "$ARTIFACT")" == "$EXPECTED_KERNEL_SHA" ]] || fail "formal CI artifact sha256 mismatch"
[[ "$(tr -d '\r\n' < "$ARTIFACT_SOURCE")" == "$FORMAL_SOURCE_COMMIT" ]] || fail "formal CI artifact source commit mismatch"
pass "candidate Image.gz-dtb matches formal a180aa33 CI artifact ($kernel_sha)"

for opt in \
  CONFIG_PID_NS CONFIG_IPC_NS CONFIG_USER_NS CONFIG_POSIX_MQUEUE \
  CONFIG_DEVPTS_MULTIPLE_INSTANCES CONFIG_CGROUP_DEVICE CONFIG_CGROUP_PIDS \
  CONFIG_MEMCG_KMEM CONFIG_MEMCG_SWAP CONFIG_VETH CONFIG_BRIDGE_NETFILTER \
  CONFIG_MACVLAN CONFIG_IPVLAN CONFIG_VXLAN CONFIG_NETFILTER_XT_MATCH_ADDRTYPE \
  CONFIG_NF_NAT_IPV4 CONFIG_NF_CT_NETLINK; do
  grep -qx "$opt=y" "$ARTIFACT_CONFIG" || fail "$opt missing from formal CI kernel config"
done
! grep -qx 'CONFIG_USB_DUMMY_HCD=y' "$ARTIFACT_CONFIG" || fail "unsafe CONFIG_USB_DUMMY_HCD enabled in formal CI artifact"
pass "formal CI artifact contains validated Docker Kconfig set and keeps USB_DUMMY_HCD disabled"

TMP="$(mktemp -d /tmp/nx563j-nh-validate.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/baseline"
unzip -qq "$BASELINE_KERNEL_ZIP" 'Image.gz-dtb' 'ramdisk-patch/*' -d "$TMP/baseline"
[[ "$(sha256_file "$TMP/baseline/Image.gz-dtb")" == "$BASELINE_KERNEL_SHA" ]] || fail "2026-09-16 hardware baseline kernel hash changed"
for f in keyboard-descriptor.bin mouse-descriptor.bin; do
  [[ "$(sha256_file "$TMP/baseline/ramdisk-patch/$f")" == "$(sha256_file "$CANDIDATE/ramdisk/$f")" ]] || fail "$f differs from hardware-tested baseline ZIP"
done
pass "hardware-tested baseline ZIP still anchors HID descriptors; formal kernel provenance is checked separately"

# init.nethunter.rc is based on the hardware-tested ZIP, with two reviewed
# functional corrections: (1) NX563J creates USB configfs/g1 too late for the
# template's `on boot` function initialization, so initialize at
# sys.boot_completed=1; (2) the Mac reset/reset+adb property triggers were
# incorrectly duplicated as win,* triggers. Build the expected executable rc
# from the tested one by applying exactly those corrections.
python3 - "$TMP/baseline/ramdisk-patch/init.nethunter.rc" "$TMP/expected.rc" <<'PY'
from pathlib import Path
import sys

src = Path(sys.argv[1]).read_text().splitlines()
out = []
in_mac = False
for raw in src:
    line = raw.rstrip()
    if line.strip() == "on boot":
        line = "on property:sys.boot_completed=1"
    if line.strip() == "# -- Against Mac OS -- #":
        in_mac = True
    if in_mac:
        line = line.replace("sys.usb.config=win,reset,adb", "sys.usb.config=mac,reset,adb")
        line = line.replace("sys.usb.config=win,reset", "sys.usb.config=mac,reset")
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    out.append(line)
Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
python3 - "$CANDIDATE/ramdisk/init.nethunter.rc" "$TMP/candidate.rc" <<'PY'
from pathlib import Path
import sys

out = []
for raw in Path(sys.argv[1]).read_text().splitlines():
    line = raw.rstrip()
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    out.append(line)
Path(sys.argv[2]).write_text("\n".join(out) + "\n")
PY
cmp -s "$TMP/expected.rc" "$TMP/candidate.rc" || fail "init.nethunter.rc has unreviewed functional changes"
pass "init.nethunter.rc matches tested ZIP plus reviewed NX563J timing + Mac reset fixes"

python3 - "$CANDIDATE/ramdisk/init.nethunter.rc" <<'PY'
from pathlib import Path
from collections import Counter
import sys

triggers = [
    line.strip() for line in Path(sys.argv[1]).read_text().splitlines()
    if line.strip().startswith("on property:")
]
dups = [item for item, count in Counter(triggers).items() if count > 1]
if dups:
    raise SystemExit("duplicate property triggers: " + "; ".join(dups))
required = {
    "on property:sys.usb.config=mac,reset && property:sys.usb.configfs=1",
    "on property:sys.usb.config=mac,reset,adb && property:sys.usb.configfs=1",
    "on property:sys.usb.ffs.ready=1 && property:sys.usb.config=mac,reset,adb && property:sys.usb.configfs=1",
}
missing = sorted(required.difference(triggers))
if missing:
    raise SystemExit("missing reviewed Mac reset triggers: " + "; ".join(missing))
PY
pass "ramdisk property triggers are unique and Mac reset profiles are present"

# NX563J uses a Magisk-patched system-as-root boot image. The device-specific
# AnyKernel hook must alias the upstream split_img typo and install the rc via
# Magisk overlay.d instead of losing it in the kernel-only SAR path.
sh -n "$SAR_PATCH" || fail "NX563J SAR AnyKernel patch has shell syntax errors"
grep -Fq 'splitimg="$split_img"' "$SAR_PATCH" || fail "SAR patch does not alias splitimg to split_img"
grep -Fq 'overlay.d/init.nethunter.rc' "$SAR_PATCH" || fail "SAR patch does not install init.nethunter.rc through overlay.d"
grep -Fq '${MAGISKTMP}/keyboard-descriptor.bin' "$SAR_PATCH" || fail "SAR patch lacks MAGISKTMP keyboard descriptor path"
grep -Fq '${MAGISKTMP}/mouse-descriptor.bin' "$SAR_PATCH" || fail "SAR patch lacks MAGISKTMP mouse descriptor path"
pass "NX563J SAR AnyKernel patch contains reviewed split_img + Magisk overlay logic"

SIM="$TMP/sar-sim"
mkdir -p "$SIM/home/ramdisk-patch" "$SIM/ramdisk/overlay.d"
cp "$CANDIDATE/ramdisk/init.nethunter.rc" "$SIM/home/ramdisk-patch/"
cp "$CANDIDATE/ramdisk/keyboard-descriptor.bin" "$SIM/home/ramdisk-patch/"
cp "$CANDIDATE/ramdisk/mouse-descriptor.bin" "$SIM/home/ramdisk-patch/"
(
  home="$SIM/home"
  ramdisk="$SIM/ramdisk"
  split_img="$SIM/split_img"
  ui_print() { :; }
  repack_ramdisk() { :; }
  flash_boot() { :; }
  flash_dtbo() { :; }
  insert_after_last() { :; }
  # shellcheck disable=SC1090
  . "$SAR_PATCH"
  [[ "$splitimg" == "$split_img" ]] || exit 1
  write_boot
) || fail "SAR AnyKernel hook simulation failed"
grep -Fq 'copy ${MAGISKTMP}/keyboard-descriptor.bin' "$SIM/ramdisk/overlay.d/init.nethunter.rc" || fail "simulated overlay rc keyboard path is wrong"
grep -Fq 'copy ${MAGISKTMP}/mouse-descriptor.bin' "$SIM/ramdisk/overlay.d/init.nethunter.rc" || fail "simulated overlay rc mouse path is wrong"
cmp -s "$SIM/ramdisk/overlay.d/sbin/keyboard-descriptor.bin" "$CANDIDATE/ramdisk/keyboard-descriptor.bin" || fail "simulated overlay keyboard descriptor differs"
cmp -s "$SIM/ramdisk/overlay.d/sbin/mouse-descriptor.bin" "$CANDIDATE/ramdisk/mouse-descriptor.bin" || fail "simulated overlay mouse descriptor differs"
pass "NX563J SAR AnyKernel overlay simulation PASS"

PRE="$TMP/premr"
mkdir -p "$PRE"
unzip -qq "$PREMR_ZIP" \
  'Image.gz-dtb' \
  'ramdisk-patch/init.nethunter.rc' \
  'ramdisk-patch/keyboard-descriptor.bin' \
  'ramdisk-patch/mouse-descriptor.bin' \
  'ak_patches/01-nx563j-magisk-sar-ramdisk.sh' \
  -d "$PRE"
cmp -s "$PRE/Image.gz-dtb" "$CANDIDATE/Image.gz-dtb" || fail "current pre-MR ZIP kernel differs from formal candidate"
python3 - "$PRE/ramdisk-patch/init.nethunter.rc" "$CANDIDATE/ramdisk/init.nethunter.rc" <<'PY'
from pathlib import Path
import sys

def normalize(path: str) -> str:
    lines = Path(path).read_text().splitlines()
    while lines and not lines[-1].strip():
        lines.pop()
    return "\n".join(line.rstrip() for line in lines) + "\n"

if normalize(sys.argv[1]) != normalize(sys.argv[2]):
    raise SystemExit("pre-MR ZIP rc has non-whitespace differences from candidate")
PY
cmp -s "$PRE/ramdisk-patch/keyboard-descriptor.bin" "$CANDIDATE/ramdisk/keyboard-descriptor.bin" || fail "pre-MR ZIP keyboard descriptor differs"
cmp -s "$PRE/ramdisk-patch/mouse-descriptor.bin" "$CANDIDATE/ramdisk/mouse-descriptor.bin" || fail "pre-MR ZIP mouse descriptor differs"
cmp -s "$PRE/ak_patches/01-nx563j-magisk-sar-ramdisk.sh" "$SAR_PATCH" || fail "pre-MR ZIP SAR patch differs from candidate"
pass "current Docker pre-MR ZIP matches formal candidate kernel/descriptors/SAR patch; rc differs only by whitespace normalization"

if command -v ruby >/dev/null 2>&1; then
  ruby -e 'require "yaml"; x=YAML.load_file(ARGV[0]); abort("expected one top-level list item") unless x.is_a?(Array) && x.length==1' "$KALI/devices.yml.nx563j"
  pass "devices.yml.nx563j parses as YAML"
else
  echo "[WARN] ruby unavailable; YAML parse check skipped"
fi

grep -q '^ *- nx563j:' "$KALI/devices.yml.nx563j" || fail "nx563j device entry missing"
grep -q 'id *: nx563j-los' "$KALI/devices.yml.nx563j" || fail "nx563j-los id missing"
grep -q 'android: fifteen' "$KALI/devices.yml.nx563j" || fail "Android fifteen entry missing"
grep -q 'linux *: 4\.04' "$KALI/devices.yml.nx563j" || fail "Linux 4.04 entry missing"
grep -q 'features *: \[BT_RFCOMM, CDROM, Docker, HID-4, Injection, QCACLD, Internal_BT, NFS\]' "$KALI/devices.yml.nx563j" || fail "reviewed feature list changed"
pass "device metadata contains reviewed Android/kernel/features values"

if [[ "${SKIP_REMOTE:-0}" != "1" ]]; then
  remote_head=""
  for attempt in 1 2 3; do
    remote_head="$(git ls-remote "$SOURCE_REPO" "refs/heads/$SOURCE_BRANCH" 2>/dev/null | awk 'NR==1{print $1}' || true)"
    [[ -n "$remote_head" ]] && break
    sleep "$attempt"
  done
  if [[ -n "$remote_head" ]]; then
    echo "[INFO] source $SOURCE_BRANCH head: $remote_head"
    pass "public kernel source branch reachable"
  elif [[ "${STRICT_REMOTE:-0}" == "1" ]]; then
    fail "public source branch not reachable after 3 attempts"
  else
    echo "[WARN] public source branch check unavailable after 3 attempts; rerun with STRICT_REMOTE=1 before MR"
  fi
else
  echo "[INFO] remote source check skipped (SKIP_REMOTE=1)"
fi

printf '\nNX563J NetHunter MR candidate validation: PASS\n'
