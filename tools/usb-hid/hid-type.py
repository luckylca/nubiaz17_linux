#!/usr/bin/env python3
# hid-type.py — type a string through /dev/hidg0 (NX563J HID keyboard).
# Safe default payload per project rules: only "NX563J HID TEST".
#
# Usage: python3 hid-type.py [text] [--dev /dev/hidg0] [--delay 0.05]
import sys, time, argparse

# HID usage IDs (USB HID Usage Tables, Keyboard/Keypad page 0x07)
KEYMAP = {}
for i, c in enumerate("abcdefghijklmnopqrstuvwxyz"):
    KEYMAP[c] = 0x04 + i
for i, c in enumerate("1234567890"):
    KEYMAP[c] = 0x1E + i
KEYMAP.update({
    " ": 0x2C, "-": 0x2D, "=": 0x2E, "[": 0x2F, "]": 0x30, "\\": 0x31,
    ";": 0x33, "'": 0x34, "`": 0x35, ",": 0x36, ".": 0x37, "/": 0x38,
    "\n": 0x28,
})
SHIFTED = {
    "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6",
    "&": "7", "*": "8", "(": "9", ")": "0", "_": "-", "+": "=",
    "{": "[", "}": "]", "|": "\\", ":": ";", '"': "'", "~": "`",
    "<": ",", ">": ".", "?": "/",
}

def report(mod, key):
    return bytes([mod, 0, key, 0, 0, 0, 0, 0])

def type_text(dev, text, delay):
    with open(dev, "wb", buffering=0) as f:
        for ch in text:
            mod = 0
            c = ch
            if ch.isupper():
                mod = 0x02  # left shift
                c = ch.lower()
            elif ch in SHIFTED:
                mod = 0x02
                c = SHIFTED[ch]
            key = KEYMAP.get(c)
            if key is None:
                continue
            f.write(report(mod, key))
            f.write(report(0, 0))
            time.sleep(delay)

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("text", nargs="?", default="NX563J HID TEST")
    ap.add_argument("--dev", default="/dev/hidg0")
    ap.add_argument("--delay", type=float, default=0.05)
    a = ap.parse_args()
    type_text(a.dev, a.text, a.delay)
    print("typed %d chars to %s" % (len(a.text), a.dev))

if __name__ == "__main__":
    main()
