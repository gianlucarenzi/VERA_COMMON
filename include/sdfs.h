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

/* Close the open file or directory.  A file written is complete on the
 * card only now (its last sector, its directory entry, the FAT): 1 = ok.
 * With libvera_sdro.lib there is nothing to write back and the value means
 * nothing. */
unsigned char sd_close(void);

/* Writing (libvera_sd.lib, the default).  libvera_sdro.lib, the FAT32 code
 * built read only for the programs short of memory (LIBVERA_SDRO_LIB: about
 * 3.3 KB less), has none of these: a program that calls them does not link
 * with it.  One file open at a time, as for reading. */

/* A new file, open to write: an existing one is replaced if overwrite,
 * else SD_ERR_EXISTS.  1 = ok. */
unsigned char __fastcall__ sd_create(const char *path, unsigned char overwrite);

/* n bytes to the file open to write; 1 = all written. */
unsigned char __fastcall__ sd_write(const void *src, unsigned n);

/* n bytes from the VERA data port 0 (the caller has set the address with
 * vram_seek) to the file open to write; 1 = all written. */
unsigned char __fastcall__ sd_write_vram(unsigned n);

/* The date and time of the files and directories made from now on.  An
 * RTC adapter comes first when there is one (plat_rtc, plat.h: the R-Time 8
 * on the Atari, a DS1307 on the C64's user port, the X16's own clock, a
 * No-Slot Clock on the Apple IIe); else
 * the time set here; else 1980-01-01 00:00:00, the first date FAT has.
 * year 1980-2107, month 1-12, day 1-31, hour 0-23. */
struct sd_time {
    unsigned int  year;
    unsigned char month, day, hour, minute, second;
};
void __fastcall__ sd_set_time(const struct sd_time *t);
/* The time the next file gets; 1 = from an RTC adapter. */
unsigned char __fastcall__ sd_get_time(struct sd_time *t);

/* Delete a file, rename (or move) a file or directory, make a directory,
 * remove an empty one; 1 = ok.  No file may be open. */
unsigned char __fastcall__ sd_delete(const char *path);
unsigned char __fastcall__ sd_rename(const char *from, const char *to);
unsigned char __fastcall__ sd_mkdir(const char *path);
unsigned char __fastcall__ sd_rmdir(const char *path);

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
