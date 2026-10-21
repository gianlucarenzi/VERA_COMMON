/*
 * asset_dsk.c - Atari: the game's data files (asset.h) on the raw sectors
 * of a DOS 2 disk, through the own IRQ driven SIO driver (sio.s): the disk
 * loads while the music plays (rmt.h, rmt_out_host), which the OS SIO
 * (asset.c, CIO and DOS) cannot do safely.
 *
 * Same API as asset.c: a program linked with libvera_dsk.lib before
 * libvera.lib takes these functions instead.  No DOS is needed in memory
 * once the program runs.  Read only DOS 2.x / MyDOS filesystem (from AT2019
 * PokeyATest dos2fs.c): directory in sectors 361-368, 128 byte sectors (SD
 * and ED disks, e.g. dir2atr -E -b Dos25), D1:.
 *
 * Every open file is one SIO transfer for the music: asset_open calls
 * rmt_io_begin, asset_close rmt_io_end (POKEY channels 3+4 are the serial
 * clock in between, only channels 1+2 play).
 */

#include <string.h>

#include "vmem.h"
#include "rmt.h"
#include "asset.h"

unsigned char __fastcall__ sio_read_sector(unsigned char unit, unsigned sector, void *buf);

#define DIR_FIRST   361
#define DIR_LAST    368
#define RETRIES     3
#define UNIT        1

#define FLAG_DELETED  0x80
#define FLAG_INUSE    0x43              /* $42 DOS 2; $03 DOS 2.5: the file
                                           uses sectors above 719 (ED) */
#define FLAG_NOFILENO 0x04              /* MyDOS: 16 bit links, no file number */

unsigned char asset_buf[ASSET_BUF_SIZE];

/* the last failure, for a diagnostic: SIO status (138 timeout, 139 NAK,
 * 140 framing, 143 checksum, 144 device error; 0 = chain error) and sector */
unsigned char asset_dsk_status;
unsigned asset_dsk_sector;

static unsigned char sec[128];
static unsigned next;                   /* next sector of the file, 0 = none */
static unsigned char fileno, flag;
static unsigned char pos, cnt;          /* bytes of sec taken / held */
static unsigned char is_open;
static char name83[11];

static unsigned char read_sector(unsigned s)
{
    unsigned char n;

    for (n = 0; n < RETRIES; ++n)
        if ((asset_dsk_status = sio_read_sector(UNIT, s, sec)) == 1)
            return 1;
    asset_dsk_sector = s;
    return 0;
}

/* the next sector of the file into sec; 0 = end of file or error */
static unsigned char fill(void)
{
    if (next == 0 || !read_sector(next)) {
        next = 0;
        return 0;
    }
    if (!(flag & FLAG_NOFILENO) && (sec[125] >> 2) != fileno) {
        next = 0;                       /* the chain left the file */
        return 0;
    }
    cnt = sec[127] & 0x7F;
    if (cnt > 125) {
        next = 0;
        return 0;
    }
    pos = 0;
    if (flag & FLAG_NOFILENO)
        next = (sec[125] << 8) | sec[126];
    else
        next = ((sec[125] & 0x03) << 8) | sec[126];
    return 1;
}

unsigned char __fastcall__ asset_open(const char *name)
{
    unsigned s;
    unsigned char i, j;
    unsigned char *d;
    char c;

    asset_close();

    /* "r1field.vts" -> "R1FIELD VTS" */
    memset(name83, ' ', sizeof name83);
    for (i = j = 0; (c = name[i]) != 0 && j < 11; ++i) {
        if (c == '.') {
            j = 8;
            continue;
        }
        name83[j++] = (c >= 'a' && c <= 'z') ? (char)(c - 0x20) : c;
    }

    rmt_io_begin();
    for (s = DIR_FIRST; s <= DIR_LAST; ++s) {
        if (!read_sector(s))
            break;
        for (i = 0; i < 8; ++i) {
            d = sec + (i << 4);
            if (d[0] == 0)
                goto fail;              /* never used: end of the directory */
            if ((d[0] & FLAG_DELETED) || !(d[0] & FLAG_INUSE))
                continue;
            if (memcmp(d + 5, name83, 11) == 0) {
                flag = d[0];
                next = d[3] | (d[4] << 8);
                fileno = (unsigned char)(((s - DIR_FIRST) << 3) + i);
                pos = cnt = 0;
                is_open = 1;
                return 1;
            }
        }
    }
fail:
    rmt_io_end();
    return 0;
}

/* disks: no streaming, asset_read as always */
unsigned char asset_stream(void)
{
    return 0;
}

void asset_close(void)
{
    if (is_open) {
        is_open = 0;
        rmt_io_end();
    }
}

unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    unsigned char k;
    unsigned char *p = (unsigned char *)dst;

    while (n) {
        if (pos == cnt) {
            if (!fill())
                return 0;
            continue;                   /* a sector may hold 0 bytes */
        }
        k = cnt - pos;
        if (k > n)
            k = (unsigned char)n;
        memcpy(p, sec + pos, k);
        pos += k;
        p += k;
        n -= k;
    }
    return 1;
}

unsigned char __fastcall__ asset_skip(unsigned long n)
{
    unsigned char k;

    while (n) {
        if (pos == cnt) {
            if (!fill())
                return 0;
            continue;
        }
        k = cnt - pos;
        if (k > n)
            k = (unsigned char)n;
        pos += k;
        n -= k;
    }
    return 1;
}

unsigned char __fastcall__ asset_vram(unsigned long n)
{
    unsigned char k;

    while (n) {
        if (pos == cnt) {
            if (!fill())
                return 0;
            continue;
        }
        k = cnt - pos;
        if (k > n)
            k = (unsigned char)n;
        /* an IRQ callback may use the data ports, but it restores them
         * (vera_irq.h): the stream goes on where it was */
        vram_write(sec + pos, k);
        pos += k;
        n -= k;
    }
    return 1;
}

unsigned char __fastcall__ asset_load(const char *name, void *dst, unsigned n)
{
    unsigned char ok;

    if (!asset_open(name))
        return 0;
    ok = asset_read(dst, n);
    asset_close();
    return ok;
}
