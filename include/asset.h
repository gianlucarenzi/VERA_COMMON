#ifndef ASSET_H
#define ASSET_H

/*
 * asset.h - the game's data files, whatever the host and its disk
 * (src/common/asset.c).
 *
 * A file is named by its logical name: lower case, 8.3, ASCII as written
 * in the C source ("r1field.vts").  The host decides the rest:
 *   Atari  "D:R1FIELD.VTS" through CIO (DOS 2 disk, ATR)
 *   C64    "r1field.vts", PRG file through the KERNAL (1541 disk, D64)
 * The file contents are the same bytes on every host: the build writes the
 * same file to both disk images (tools/mkdisk.py).
 * Atari and C64 can read the files from the microSD of the VERA instead:
 * link $(LIBVERA_SD_LIB) before $(LIBVERA_LIB) (src/common/asset_sd.c),
 * the files go in the root of a FAT32 partition (tools/mksdimg.py).  The
 * X16 needs nothing: its drive 8 is the SD card.
 *
 * One file is open at a time.  The formats carry their own lengths: never
 * rely on a short read for the end of a file (Atari DOS was seen to deliver
 * data past the true end).
 */

/* Open a file for reading; 1 = ok, 0 = not found or I/O error.  A file
 * still open is closed first. */
unsigned char __fastcall__ asset_open(const char *name);

/* Read exactly n bytes; 1 = ok, 0 = I/O error or end of file. */
unsigned char __fastcall__ asset_read(void *dst, unsigned n);

/* Skip n bytes; 1 = ok. */
unsigned char __fastcall__ asset_skip(unsigned long n);

/* Stream n bytes to VRAM through DATA0, at the address and increment set
 * by vram_seek() (vmem.h); 1 = ok.  Uses asset_buf as the bounce buffer. */
unsigned char __fastcall__ asset_vram(unsigned long n);

void asset_close(void);

/* Open, read n bytes to dst, close; 1 = ok. */
unsigned char __fastcall__ asset_load(const char *name, void *dst, unsigned n);

/* The bounce buffer of asset_vram / asset_skip, free between calls. */
#define ASSET_BUF_SIZE 256u
extern unsigned char asset_buf[ASSET_BUF_SIZE];

#endif /* ASSET_H */
