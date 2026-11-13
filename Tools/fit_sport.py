#!/usr/bin/env python3
"""Rewrite the sport / sub-sport of a Garmin FIT activity file in place.

Record on the vivosmart 5 as Cardio, export the original .fit from Garmin
Connect, run this, then import the output with Connect's Import Data.

    python fit_sport.py bouldering Activity.fit            # -> Activity_bouldering.fit
    python fit_sport.py badminton in.fit -o out.fit
    python fit_sport.py --selftest
"""
import argparse
import struct
import sys
from pathlib import Path

# name -> (sport, sub_sport), values from the FIT profile
SPORTS = {
    "bouldering": (31, 69),   # rock_climbing / bouldering
    "badminton": (64, 95),    # racket / badminton
    "basketball": (6, 0),     # basketball / generic
}

# global message number -> (sport field number, sub_sport field number)
MESSAGES = {
    12: (0, 1),     # sport
    18: (5, 6),     # session
    19: (25, 39),   # lap
}


def crc16(data, crc=0):
    table = (0x0000, 0xCC01, 0xD801, 0x1400, 0xF001, 0x3C00, 0x2800, 0xE401,
             0xA001, 0x6C00, 0x7800, 0xB401, 0x5000, 0x9C01, 0x8801, 0x4400)
    for b in data:
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[b & 0xF]
        tmp = table[crc & 0xF]
        crc = (crc >> 4) & 0x0FFF
        crc = crc ^ tmp ^ table[(b >> 4) & 0xF]
    return crc


def retag(buf, sport, sub_sport):
    """Patch buf (bytearray) in place; return number of fields changed."""
    hdr = buf[0]
    if hdr not in (12, 14):
        raise ValueError("not a FIT file")
    if bytes(buf[8:12]) != b".FIT":
        raise ValueError("not a FIT file")
    data_size = struct.unpack_from("<I", buf, 4)[0]
    end = hdr + data_size
    if end + 2 > len(buf):
        raise ValueError("truncated FIT file")

    defs = {}   # local type -> (global, big_endian, [(num, size, offset)], total_size, dev_size)
    pos = hdr
    changed = 0
    while pos < end:
        h = buf[pos]
        pos += 1
        if h & 0x80:                       # compressed timestamp data message
            local = (h >> 5) & 0x3
            is_def = False
        else:
            local = h & 0x0F
            is_def = bool(h & 0x40)
        if is_def:
            has_dev = bool(h & 0x20)
            big = buf[pos + 1] == 1
            glob = struct.unpack_from(">H" if big else "<H", buf, pos + 2)[0]
            n = buf[pos + 4]
            pos += 5
            fields, off = [], 0
            for _ in range(n):
                num, size = buf[pos], buf[pos + 1]
                fields.append((num, size, off))
                off += size
                pos += 3
            dev = 0
            if has_dev:
                nd = buf[pos]
                pos += 1
                for _ in range(nd):
                    dev += buf[pos + 1]
                    pos += 3
            defs[local] = (glob, fields, off + dev)
        else:
            glob, fields, total = defs[local]
            if glob in MESSAGES:
                want = dict(zip(MESSAGES[glob], (sport, sub_sport)))
                for num, size, off in fields:
                    if num in want and size == 1 and buf[pos + off] != want[num]:
                        buf[pos + off] = want[num]
                        changed += 1
            pos += total

    if hdr == 14:
        struct.pack_into("<H", buf, 12, crc16(buf[:12]))
    struct.pack_into("<H", buf, end, crc16(buf[:end]))
    return changed


def selftest():
    # minimal file: sport(12) + session(18) + lap(19), little endian
    body = bytearray()
    for glob, (sf, ssf) in MESSAGES.items():
        body += bytes([0x40, 0, 0]) + struct.pack("<H", glob) + bytes([2, sf, 1, 2, ssf, 1, 2])
        body += bytes([0x00, 2, 0])          # cardio-ish: training / generic... overwritten below
    hdr = bytearray(struct.pack("<BBHI4s", 12, 0x20, 2000, len(body), b".FIT"))
    buf = hdr + body + b"\0\0"
    struct.pack_into("<H", buf, len(buf) - 2, crc16(buf[:-2]))
    n = retag(buf, *SPORTS["bouldering"])
    assert n == 6, n
    assert struct.unpack_from("<H", buf, len(buf) - 2)[0] == crc16(buf[:-2])
    assert [b for b in buf[12:] if b in (31, 69)] == [31, 69] * 3
    print("selftest ok")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    p.add_argument("sport", nargs="?", choices=sorted(SPORTS))
    p.add_argument("fit", nargs="?", type=Path)
    p.add_argument("-o", "--output", type=Path)
    p.add_argument("--selftest", action="store_true")
    a = p.parse_args()
    if a.selftest:
        return selftest()
    if not a.sport or not a.fit:
        p.error("sport and fit file are required")
    buf = bytearray(a.fit.read_bytes())
    n = retag(buf, *SPORTS[a.sport])
    out = a.output or a.fit.with_name(f"{a.fit.stem}_{a.sport}{a.fit.suffix}")
    out.write_bytes(buf)
    print(f"{out}: {n} field(s) changed")


if __name__ == "__main__":
    sys.exit(main())
