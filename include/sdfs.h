#ifndef SDFS_H
#define SDFS_H

/*
 * sdfs.h - files on the microSD card of the VERA (SPI at VERA_BASE + $1E),
 * FAT32: the X16 KERNAL code (x16-rom fat32/, Frank van den Hoef and
 * Michael Steil, 2-clause BSD) ported to the NMOS 6502 (src/fat32/).
 *
 * One file or directory open at a time (context 0 of the first volume).
 * Names: '/' separated paths, any case (FAT32 compares them without case);
 * C strings are converted to ASCII on the C64 and the X16 (PETSCII there).
 *
 * Emulators: x64sc -verasdcard <img>, atari800 -verax16-sdcard <img>,
 * x16emu -sdcard <img>.  Code ~9.5 KB, RAM ~2.3 KB, 10 bytes of zero page.
 */

/* fat32_errno values */
#define SD_OK               0
#define SD_ERR_READ         1
#define SD_ERR_WRITE        2
#define SD_ERR_NAME         3
#define SD_ERR_EXISTS       4
#define SD_ERR_NOT_FOUND    5
#define SD_ERR_READ_ONLY    6
#define SD_ERR_NOT_EMPTY    7
#define SD_ERR_NO_MEDIA     8
#define SD_ERR_NO_FS        9
#define SD_ERR_INCONSISTENT 10
#define SD_ERR_PROTECTED    11
#define SD_ERR_RESOURCES    12

#define SD_ATTR_DIR         0x10

/* the entry sd_readdir() decoded (the X16 struct dirent) */
struct sd_dirent {
    char          name[256];            /* ASCII, long name if there is one */
    unsigned char attributes;           /* SD_ATTR_DIR, ... */
    unsigned long start;                /* first cluster */
    unsigned long size;                 /* bytes */
    unsigned char mtime[6];             /* year - 1980, month, day, h, m, s */
};
extern struct sd_dirent sd_dirent;

/* Card and the first FAT32 volume (MBR partition or the whole card).
 * 1 = ready, 0 = no card / no FAT32 (sd_errno()). */
unsigned char sd_mount(void);

/* Open a file to read; 1 = ok. */
unsigned char __fastcall__ sd_open(const char *path);

/* Up to n bytes to dst; returns how many were read, less than n at the end
 * of the file (0 = at the end or error: sd_errno()). */
unsigned __fastcall__ sd_read(void *dst, unsigned n);

/* Up to n bytes to the VERA data port 0 (the caller has set the address
 * with vram_seek): straight from the sector buffer to VRAM. */
unsigned __fastcall__ sd_read_vram(unsigned n);

void sd_close(void);

/* The open file as one stream (src/fat32/sdstream.s): sd_stream_start right
 * after sd_open (1 = the file is contiguous and the card streams it, 0 =
 * not: sd_read works as before), sd_stream_reset, then only
 * sd_stream_read / sd_stream_vram (n bytes, or 0 on a card error) until
 * sd_stream_stop, before sd_close.  The card stays busy with the file. */
unsigned char sd_stream_start(void);
void sd_stream_reset(void);
unsigned __fastcall__ sd_stream_read(void *dst, unsigned n);
unsigned __fastcall__ sd_stream_vram(unsigned n);
void sd_stream_stop(void);

/* Open a directory ("" = the current one) and read its entries into
 * sd_dirent; sd_readdir() returns 0 after the last one. Close it with
 * sd_close() before opening anything else (one context only). */
unsigned char __fastcall__ sd_opendir(const char *path);
unsigned char sd_readdir(void);

/* Change the current directory; 1 = ok. */
unsigned char __fastcall__ sd_chdir(const char *path);

/* The last error (SD_ERR_*, 0 = none). */
unsigned char sd_errno(void);

#endif /* SDFS_H */
