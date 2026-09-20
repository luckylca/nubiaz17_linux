#!/usr/bin/env python3
"""NX563J SLCAN software smoke test using a pseudo-terminal.

No external CAN or serial hardware is required. The test attaches the kernel
N_SLCAN line discipline to a PTY slave, then validates both directions:
CAN_RAW -> SLCAN ASCII and SLCAN ASCII -> CAN_RAW.
"""

import fcntl
import os
import pty
import select
import socket
import struct
import subprocess
import termios
import time
import tty

# Direct chroot invocations may start with Android's minimal PATH.
os.environ["PATH"] = (
    "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:"
    + os.environ.get("PATH", "")
)

TIOCSETD = 0x5423
N_SLCAN = 17
CAN_FRAME = struct.Struct("=IB3x8s")
IFACE = "slcan0"


def run(*args: str) -> str:
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT).strip()


def wait_iface(name: str, timeout: float = 2.0) -> None:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if os.path.exists(f"/sys/class/net/{name}"):
            return
        time.sleep(0.02)
    raise RuntimeError(f"{name} was not created by N_SLCAN")


def read_until(fd: int, marker: bytes = b"\r", timeout: float = 2.0) -> bytes:
    data = bytearray()
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        left = max(0.0, end - time.monotonic())
        readable, _, _ = select.select([fd], [], [], left)
        if not readable:
            break
        chunk = os.read(fd, 256)
        data.extend(chunk)
        if marker in data:
            return bytes(data)
    raise RuntimeError(f"timeout waiting for PTY data; got {bytes(data)!r}")


def pack(can_id: int, payload: bytes) -> bytes:
    if len(payload) > 8:
        raise ValueError("classic CAN payload exceeds 8 bytes")
    return CAN_FRAME.pack(can_id, len(payload), payload.ljust(8, b"\0"))


def unpack(raw: bytes) -> tuple[int, bytes]:
    can_id, dlc, data = CAN_FRAME.unpack(raw)
    return can_id, data[:dlc]


def main() -> None:
    if os.geteuid() != 0:
        raise SystemExit("run as root")

    # Ensure a prior interrupted test cannot leave the interface behind.
    subprocess.run(["ip", "link", "del", IFACE], stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL)

    master, slave = pty.openpty()
    try:
        tty.setraw(slave)
        fcntl.ioctl(slave, TIOCSETD, struct.pack("i", N_SLCAN))
        wait_iface(IFACE)
        run("ip", "link", "set", IFACE, "up")

        tx = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
        tx.bind((IFACE,))
        try:
            # Kernel CAN -> serial ASCII path. Do this before opening the RX
            # socket so CAN core's normal local-loopback copy cannot be mistaken
            # for the later serial->CAN test frame.
            tx_payload = b"NX563J"
            tx.send(pack(0x563, tx_payload))
            ascii_out = read_until(master)
            expected_ascii = b"t5636" + tx_payload.hex().upper().encode() + b"\r"
            if expected_ascii not in ascii_out:
                raise RuntimeError(
                    f"SLCAN TX mismatch: expected {expected_ascii!r}, got {ascii_out!r}"
                )

            # Serial ASCII -> kernel CAN path. Open RX only after the TX test so
            # there is no queued local-loopback frame from the 0x563 send above.
            rx = socket.socket(socket.AF_CAN, socket.SOCK_RAW, socket.CAN_RAW)
            rx.bind((IFACE,))
            rx.settimeout(2.0)
            try:
                rx_id = 0x456
                rx_payload = b"Z17"
                ascii_in = b"t4563" + rx_payload.hex().upper().encode() + b"\r"
                os.write(master, ascii_in)
                got_id, got_payload = unpack(rx.recv(CAN_FRAME.size))
                if got_id != rx_id or got_payload != rx_payload:
                    raise RuntimeError(
                        f"SLCAN RX mismatch: id=0x{got_id:x} data={got_payload!r}"
                    )

                print(
                    "SLCAN_PTY_PASS "
                    f"interface={IFACE} "
                    f"tx_ascii={expected_ascii.decode().strip()} "
                    f"rx_id=0x{got_id:x} rx_data={got_payload.decode()}"
                )
            finally:
                rx.close()
        finally:
            tx.close()
    finally:
        # Closing the N_SLCAN tty removes slcan0; retain an explicit cleanup too.
        os.close(slave)
        os.close(master)
        subprocess.run(["ip", "link", "del", IFACE], stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
