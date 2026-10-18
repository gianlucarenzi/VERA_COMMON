/*
 * asset_sd.c - the game's data files on the microSD of the VERA (see
 * asset.h), through the FAT32 code of src/fat32 (sdfs.h).
 *
 * Same API as asset.c: a program linked with libvera_sd.lib before
 * libvera.lib takes these functions instead of the disk ones, the game
 * does not change.  The files are in the root directory of the first
 * partition, with their logical names ("r1field.vts"); the FAT32 code
 * matches the names without regard to case.  The card is mounted by the
 * first asset_open.
 *
 * Atari and C64 only: on the X16 the KERNAL's drive 8 is already the SD
 * card, asset.c reads it.
 */

#include "vmem.h"
#include "sdfs.h"
#include "asset.h"

unsigned char asset_buf[ASSET_BUF_SIZE];

static unsigned char mounted;
static unsigned char is_open;

unsigned char __fastcall__ asset_open(const char *name)
{
    asset_close();
    if (!mounted) {
        if (!sd_mount())
            return 0;
        mounted = 1;
    }
    is_open = sd_open(name);
    return is_open;
}

void asset_close(void)
{
    if (is_open) {
        sd_close();
        is_open = 0;
    }
}

unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    unsigned got;
    unsigned char *p = (unsigned char *)dst;

    while (n) {
        got = sd_read(p, n);
        if (got == 0)
            return 0;
        p += got;
        n -= got;
    }
    return 1;
}

unsigned char __fastcall__ asset_skip(unsigned long n)
{
    unsigned chunk;

    while (n) {
        chunk = n > ASSET_BUF_SIZE ? ASSET_BUF_SIZE : (unsigned)n;
        if (!asset_read(asset_buf, chunk))
            return 0;
        n -= chunk;
    }
    return 1;
}

unsigned char __fastcall__ asset_vram(unsigned long n)
{
    unsigned chunk, got;

    /* straight from the sector buffer to DATA0, no bounce buffer; an IRQ
     * callback that uses the data ports restores them (vera_irq.h) */
    while (n) {
        chunk = n > 0x4000 ? 0x4000 : (unsigned)n;
        got = sd_read_vram(chunk);
        if (got == 0)
            return 0;
        n -= got;
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
