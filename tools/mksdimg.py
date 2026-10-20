#!/usr/bin/env python3
"""
mksdimg.py - a microSD image for the VERA: MBR + one FAT32 partition
(type $0C at LBA 2048, what the X16 FAT32 code mounts), the given files in
its root directory.

Usage: mksdimg.py [-s MB] [-c SECTORS] [-n LABEL] out.img file...

-c: sectors per cluster (default: mkfs.fat's choice, 1 on 64 MB).  The FAT32
code reads the FAT into the same sector buffer at every cluster boundary:
with 1-sector clusters every data sector costs two card reads.  Real cards
use 4-32 KB clusters; FAT32 needs >= 65525 clusters (4 KB: >= 256 MB).
The image is written sparse.

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
    ap.add_argument("-c", "--cluster", type=int, help="sectors per cluster")
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
        subprocess.run([mkfs, "-F", "32", "-h", str(PART_LBA), "-n", a.label]
                       + (["-s", str(a.cluster)] if a.cluster else []) + [part],
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
            out.seek(512 * PART_LBA)
            while True:                     # sparse: skip the zero blocks
                b = p.read(1 << 16)
                if not b:
                    break
                if b.count(0) == len(b):
                    out.seek(len(b), 1)
                else:
                    out.write(b)
            out.truncate(512 * (PART_LBA + sectors))


if __name__ == "__main__":
    main()
