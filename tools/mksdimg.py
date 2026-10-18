#!/usr/bin/env python3
"""
mksdimg.py - a microSD image for the VERA: MBR + one FAT32 partition
(type $0C at LBA 2048, what the X16 FAT32 code mounts), the given files in
its root directory.

Usage: mksdimg.py [-s MB] [-n LABEL] out.img file...

Needs mkfs.fat (/usr/sbin) and mtools (mcopy).
"""

import argparse
import os
import shutil
import subprocess
import tempfile

PART_LBA = 2048


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-s", "--size", type=int, default=64, help="partition MB (default 64)")
    ap.add_argument("-n", "--label", default="VERA")
    ap.add_argument("out")
    ap.add_argument("files", nargs="*")
    a = ap.parse_args()

    sectors = a.size * 2048
    with tempfile.TemporaryDirectory() as tmp:
        part = os.path.join(tmp, "part.img")
        with open(part, "wb") as f:
            f.truncate(sectors * 512)
        mkfs = shutil.which("mkfs.fat") or "/usr/sbin/mkfs.fat"
        subprocess.run([mkfs, "-F", "32", "-h", str(PART_LBA), "-n", a.label, part],
                       check=True, stdout=subprocess.DEVNULL)
        if a.files:
            subprocess.run(["mcopy", "-o", "-i", part] + a.files + ["::"], check=True)

        mbr = bytearray(512)
        e = 0x1BE
        mbr[e + 4] = 0x0C
        mbr[e + 8:e + 12] = PART_LBA.to_bytes(4, "little")
        mbr[e + 12:e + 16] = sectors.to_bytes(4, "little")
        mbr[510:512] = b"\x55\xAA"
        with open(a.out, "wb") as out, open(part, "rb") as p:
            out.write(mbr)
            out.write(bytes(512 * (PART_LBA - 1)))
            shutil.copyfileobj(p, out)


if __name__ == "__main__":
    main()
