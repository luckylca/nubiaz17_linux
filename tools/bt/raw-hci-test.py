#!/usr/bin/env python3
# raw-hci-test.py — Phase 7 proof: userspace raw HCI socket on NX563J.
#
# Opens an AF_BLUETOOTH/SOCK_RAW/BTPROTO_HCI socket bound to hci0, sends
# HCI_Read_Local_Version_Information (0x1001) and HCI_Read_BD_ADDR (0x1009)
# as raw command packets, and parses the Command Complete events. This is
# exactly the channel NetHunter tools (hcitool cmd, gatttool internals,
# bettercap) use — a PASS here proves raw HCI works without bluetoothd in
# the way.
import socket
import struct
import sys

HCI_COMMAND_PKT = 0x01
HCI_EVENT_PKT = 0x04
EVT_CMD_COMPLETE = 0x0E
EVT_CMD_STATUS = 0x0F

# struct hci_filter { uint32_t type_mask; uint32_t event_mask[2]; uint16_t opcode; }
# SOL_HCI = 0 (python has no constant); HCI_FILTER optname = 2 on this kernel.
SOL_HCI = 0
HCI_FILTER = 2


def set_filter(sock):
    type_mask = (1 << HCI_EVENT_PKT) | (1 << HCI_COMMAND_PKT)
    emask0 = (1 << EVT_CMD_COMPLETE) | (1 << EVT_CMD_STATUS)
    emask1 = 1 << (0x3E - 32)  # LE Meta Event
    flt = struct.pack("<IIIH", type_mask, emask0, emask1, 0)
    sock.setsockopt(SOL_HCI, HCI_FILTER, flt)


def cmd(ogf, ocf, params=b""):
    opcode = (ogf << 10) | ocf
    return bytes([HCI_COMMAND_PKT]) + struct.pack("<HB", opcode, len(params)) + params


def read_event(sock, want_opcode, timeout=3.0, verbose=False):
    sock.settimeout(timeout)
    while True:
        pkt = sock.recv(1024)
        if verbose:
            print("  rx: %s" % pkt.hex())
        if len(pkt) < 4 or pkt[0] != HCI_EVENT_PKT or pkt[1] != EVT_CMD_COMPLETE:
            continue
        # event layout: [type][event][plen][ncmd][opcode lo][opcode hi][params]
        ncmd = pkt[3]
        opcode = struct.unpack("<H", pkt[4:6])[0]
        if opcode != want_opcode:
            continue
        return pkt[6:]


def main():
    dev_id = 0  # hci0
    s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_RAW, socket.BTPROTO_HCI)
    s.bind((dev_id,))
    set_filter(s)
    print("raw HCI socket bound to hci%d" % dev_id)

    verbose = "-v" in sys.argv

    # Read Local Version Information (OGF 0x04 = info params)
    s.send(cmd(0x04, 0x0001))
    r = read_event(s, 0x1001, verbose=verbose)
    status = r[0]
    hci_ver, hci_rev, lmp_ver, mfr, lmp_subver = struct.unpack("<BHBHH", r[1:10])
    print("Local Version: status=%d hci_ver=%d hci_rev=%d lmp_ver=%d "
          "mfr=%d lmp_subver=%d" % (status, hci_ver, hci_rev, lmp_ver,
                                    mfr, lmp_subver))
    if status != 0:
        print("FAIL: nonzero status")
        return 1

    # Read BD_ADDR
    s.send(cmd(0x04, 0x0009))
    r = read_event(s, 0x1009)
    addr = ":".join("%02X" % b for b in reversed(r[1:7]))
    print("BD_ADDR: %s (status=%d)" % (addr, r[0]))
    if r[0] != 0:
        print("FAIL: nonzero status")
        return 1

    s.close()
    print("PASS: raw HCI socket command/response x2 without bluetoothd involvement")
    return 0


if __name__ == "__main__":
    sys.exit(main())
