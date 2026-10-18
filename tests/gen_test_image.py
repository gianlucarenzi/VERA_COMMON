#!/usr/bin/env python3
"""
gen_test_image.py - Generate a FAT32 SD card image for testing libvera fat32.

Usage: python3 gen_test_image.py [output.img]

Creates a FAT32 image with:
- Empty file
- Small file (1 byte)
- Medium file (512 bytes)
- Larger file (4097 bytes, multi-cluster)
- Large file (70000 bytes, fragmented if needed)
- Files with mixed case / long names
- Subdirectory with files
- Fragmented files (via copy/delete/copy pattern)

Requires: mtools, mkfs.fat
"""

import os
import subprocess
import sys
import tempfile
import shutil
from pathlib import Path

def run_cmd(cmd, check=True):
    """Run a shell command."""
    print(f"$ {cmd}")
    result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"Error: {result.stderr}")
        sys.exit(1)
    return result

def create_test_image(output_path="test_fat32.img"):
    """Create a FAT32 image with test files and a Rastan asset tree."""

    # Image parameters: MBR + one FAT32 (LBA, type $0C) partition at sector
    # 2048; the X16 FAT32 code mounts only partitions, not superfloppies
    size_kb = 65536  # 64 MB FAT32 partition
    part_lba = 2048
    final_path = output_path

    print(f"Generating FAT32 test image: {output_path}")

    # Create a temporary directory for staging files
    with tempfile.TemporaryDirectory() as tmpdir:
        staging_dir = os.path.join(tmpdir, "stage")
        os.makedirs(staging_dir)

        # Copy real Rastan assets into the image for end-to-end load tests.
        repo_root = Path(__file__).resolve().parents[2]
        rastan_root = repo_root / "RastanRIP"
        rastan_stage = Path(tmpdir) / "rastan"
        rastan_stage.mkdir(parents=True, exist_ok=True)

        for rel in ["output/vera/r1field", "output/vera/round1castle", "output/vera/round2field",
                    "output/vera/round2castle", "output/sprites"]:
            src = rastan_root / rel
            if src.exists():
                dst = rastan_stage / Path(rel).name
                if dst.exists():
                    shutil.rmtree(dst)
                shutil.copytree(src, dst)
                print(f"  - {rel} -> {dst.name}")

        palette_src = rastan_root / "output" / "palette.bin"
        if palette_src.exists():
            shutil.copy2(palette_src, rastan_stage / "palette.bin")
            print("  - palette.bin")

        # Create test files
        print("\nCreating test files...")

        # Empty file
        open(os.path.join(staging_dir, "empty.txt"), "w").close()
        print("  - empty.txt (0 bytes)")

        # 1 byte
        with open(os.path.join(staging_dir, "one.bin"), "wb") as f:
            f.write(b"X")
        print("  - one.bin (1 byte)")

        # 512 bytes (exactly one sector)
        with open(os.path.join(staging_dir, "sector.bin"), "wb") as f:
            f.write(b"A" * 512)
        print("  - sector.bin (512 bytes)")

        # 4097 bytes (multi-cluster, 2 clusters with 4KB cluster size)
        with open(os.path.join(staging_dir, "multi.bin"), "wb") as f:
            f.write(b"B" * 4097)
        print("  - multi.bin (4097 bytes)")

        # 70000 bytes (large file)
        with open(os.path.join(staging_dir, "large.bin"), "wb") as f:
            for i in range(70000):
                f.write(bytes([i & 0xFF]))
        print("  - large.bin (70000 bytes)")

        # Mixed case and long name
        with open(os.path.join(staging_dir, "MixedCaseFile.txt"), "w") as f:
            f.write("This file has mixed case and a long name\n")
        print("  - MixedCaseFile.txt")

        # Create subdirectory with files
        subdir = os.path.join(staging_dir, "subdir")
        os.makedirs(subdir)
        print("  - subdir/ (directory)")

        with open(os.path.join(subdir, "inside.txt"), "w") as f:
            f.write("File inside subdirectory\n")
        print("    - inside.txt")

        with open(os.path.join(subdir, "another.bin"), "wb") as f:
            f.write(b"C" * 1000)
        print("    - another.bin (1000 bytes)")

        # The partition is built in its own file, the MBR is added at the end
        output_path = os.path.join(tmpdir, "part.img")

        # Create the raw image (will be filled with FAT32)
        print(f"\nCreating FAT32 image ({size_kb} KB)...")
        run_cmd(f"truncate -s {size_kb}K {output_path}")

        # Format as FAT32
        print("Formatting as FAT32...")
        run_cmd(f"/usr/sbin/mkfs.fat -F 32 -h {part_lba} -n TESTCARD {output_path}")

        # Mount via mtools and copy files
        print("Copying files to image...")
        mcopy_cmd = f'mcopy -i {output_path} {staging_dir}/* ::'
        run_cmd(mcopy_cmd)
        mcopy_rastan_cmd = f'mcopy -i {output_path} -s {rastan_stage} ::/rastan'
        run_cmd(mcopy_rastan_cmd)

        # List the image contents
        print("\nImage contents:")
        run_cmd(f'mdir -i {output_path}')

        # Create fragmented files by copy-delete-copy
        # (This is optional and tests fragmentation)
        print("\nCreating fragmented files...")
        frag_path = os.path.join(staging_dir, "frag_temp.bin")
        with open(frag_path, "wb") as f:
            f.write(b"TEMP" * 5000)

        mcopy_cmd = f'mcopy -i {output_path} {frag_path} ::frag.bin'
        run_cmd(mcopy_cmd)

        # Now delete and recreate to fragment
        run_cmd(f'mdel -i {output_path} ::frag.bin')

        with open(frag_path, "wb") as f:
            f.write(b"FRAG" * 5000)
        mcopy_cmd = f'mcopy -i {output_path} {frag_path} ::frag.bin'
        run_cmd(mcopy_cmd)

        # Print image info
        run_cmd(f'minfo -i {output_path}')

        mbr = bytearray(512)
        e = 0x1BE
        mbr[e + 4] = 0x0C
        mbr[e + 8:e + 12] = part_lba.to_bytes(4, "little")
        mbr[e + 12:e + 16] = (size_kb * 2).to_bytes(4, "little")
        mbr[510:512] = b"\x55\xAA"
        with open(final_path, "wb") as out, open(output_path, "rb") as part:
            out.write(mbr)
            out.write(bytes(512 * (part_lba - 1)))
            shutil.copyfileobj(part, out)

        print(f"\nTest image created: {final_path}")
        print(f"Size: {size_kb} KB + MBR")

if __name__ == "__main__":
    output = sys.argv[1] if len(sys.argv) > 1 else "test_fat32.img"
    create_test_image(output)
