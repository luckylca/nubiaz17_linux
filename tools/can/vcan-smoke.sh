#!/usr/bin/env bash
set -euo pipefail

# Direct chroot invocations do not always inherit Kali's normal login PATH.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

# NX563J SocketCAN software smoke test.
# Requires a kernel built with CONFIG_CAN_VCAN=y and Python 3 with AF_CAN.
# No external CAN hardware is used.

VCAN_IF="${VCAN_IF:-vcan0}"

if [[ "$(id -u)" != "0" ]]; then
  echo "error: run as root" >&2
  exit 2
fi

command -v ip >/dev/null
command -v python3 >/dev/null

cleanup() {
  ip link del "$VCAN_IF" 2>/dev/null || true
}
trap cleanup EXIT
cleanup

ip link add dev "$VCAN_IF" type vcan
ip link set "$VCAN_IF" up
ip -details link show "$VCAN_IF"

VCAN_IF="$VCAN_IF" python3 - <<'PY'
import os
import socket
import struct
import time

iface = os.environ["VCAN_IF"]
if not hasattr(socket, "AF_CAN") or not hasattr(socket, "CAN_RAW"):
    raise SystemExit("Python has no AF_CAN/CAN_RAW support")

rx = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
tx = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
rx.bind((iface,))
tx.bind((iface,))
rx.settimeout(2.0)

can_id = 0x563
payload = b"NX563J"
frame = struct.pack("=IB3x8s", can_id, len(payload), payload.ljust(8, b"\0"))
tx.send(frame)

raw = rx.recv(16)
rid, dlc, data = struct.unpack("=IB3x8s", raw)
data = data[:dlc]
if rid != can_id or data != payload:
    raise SystemExit(f"CAN loopback mismatch: id=0x{rid:x} dlc={dlc} data={data!r}")

print(f"VCAN_LOOPBACK_PASS interface={iface} id=0x{rid:x} data={data.decode()}")
rx.close()
tx.close()
PY

echo "NX563J SocketCAN vcan smoke: PASS"
