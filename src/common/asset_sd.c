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

/* the code in LOWRODATA: on the Atari (cfg/atari-rambo.cfg) RAM below $4000,
 * MAIN is full; on the C64 it is in MAIN like CODE */
#pragma code-name (push, "LOWRODATA")

static unsigned char mounted;
static unsigned char is_open;
static unsigned char streaming;

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

unsigned char asset_stream(void)
{
    if (is_open && !streaming && sd_stream_start()) {
        sd_stream_reset();
        streaming = 1;
    }
    return streaming;
}

void asset_close(void)
{
    if (streaming) {
        sd_stream_stop();
        streaming = 0;
    }
    if (is_open) {
        sd_close();
        is_open = 0;
    }
}

void (*asset_progress)(unsigned n);

unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    unsigned got;
    unsigned char *p = (unsigned char *)dst;
    unsigned n0 = n;

    if (streaming) {
        if (n && sd_stream_read(dst, n) != n)
            return 0;
    } else {
        while (n) {
            got = sd_read(p, n);
            if (got == 0)
                return 0;
            p += got;
            n -= got;
        }
    }
    if (asset_progress)
        asset_progress(n0);
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
        /* smaller pieces while a loading bar follows them */
        chunk = asset_progress ? 0x800 : 0x4000;
        if (n < chunk)
            chunk = (unsigned)n;
        got = streaming ? sd_stream_vram(chunk) : sd_read_vram(chunk);
        if (got == 0)
            return 0;
        n -= got;
        if (asset_progress)
            asset_progress(got);
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

#pragma code-name (pop)
