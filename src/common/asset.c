/*
 * asset.c - the game's data files (see asset.h).
 *
 * cc65's POSIX layer (open/read/close) is the same on both hosts and much
 * smaller than stdio: on the Atari read() is one CIO call per chunk, on the
 * C64 a KERNAL CHRIN loop.  Only the file name differs.  A faster loader
 * (Atari high speed SIO, a C64 fast loader) replaces read() here, nowhere
 * else.
 */

#include <fcntl.h>
#include <unistd.h>
#include <string.h>

#include "vmem.h"
#include "asset.h"

#if defined(__C64__) || defined(__CX16__)
#include <cbm.h>
#endif

unsigned char asset_buf[ASSET_BUF_SIZE];

#if defined(__CX16__)
/* the X16: the KERNAL channel of the file, read with MACPTR (macptr.s)
 * instead of read()'s CHRIN per byte */
#define ASSET_LFN 3
unsigned __fastcall__ asset_macptr(unsigned char n, void *dst);
unsigned __fastcall__ asset_macptr_fix(unsigned char n, void *dst);
static unsigned char fd_open;
#else
static int fd = -1;
#endif

#if defined(__ATARI__)
static char path[2 + 12 + 1] = "D:";
#endif

unsigned char __fastcall__ asset_open(const char *name)
{
#if defined(__ATARI__) || defined(__CX16__)
    unsigned char i;
#endif
#if defined(__ATARI__)
    char c;
#endif

    asset_close();
#if defined(__ATARI__)
    /* "D:" + the name in upper case */
    for (i = 0; i < 12 && (c = name[i]) != 0; ++i)
        path[2 + i] = (c >= 'a' && c <= 'z') ? (char)(c - 0x20) : c;
    path[2 + i] = 0;
    fd = open(path, O_RDONLY);
#elif defined(__APPLE2__)
    /* no DOS under the a2fs boot sector: open() needs ProDOS (the game
       reads the microSD, libvera_sd.lib) */
    fd = open(name, O_RDONLY);
#elif defined(__CX16__)
    if (cbm_open(ASSET_LFN, 8, 2, name))
        return 0;
    fd_open = 1;
    /* a missing file shows in the status once the channel talks */
    cbm_k_chkin(ASSET_LFN);
    i = cbm_k_readst();
    cbm_k_clrch();
    if (i) {
        asset_close();
        return 0;
    }
    return 1;
#else
    /* the build writes the files as PRG (c1541 -write) */
    _filetype = 'p';
    fd = open(name, O_RDONLY);
#endif
#if !defined(__CX16__)
    return fd >= 0;
#endif
}

/* disks: no streaming, asset_read as always */
unsigned char asset_stream(void)
{
    return 0;
}

void asset_close(void)
{
#if defined(__CX16__)
    if (fd_open) {
        cbm_close(ASSET_LFN);
        fd_open = 0;
    }
#else
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
#endif
}

void (*asset_progress)(unsigned n);

#if defined(__CX16__)
/* the MACPTR count for n bytes left: 0 = to the end of the sector (<= 512) */
#define MACPTR_N(n) ((n) >= 512 ? 0 : (n) > 255 ? 255 : (unsigned char)(n))

unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    unsigned got;
    unsigned char *p = (unsigned char *)dst;
    unsigned n0 = n;

    /* the channel only while reading: GETIN of the game must see the
     * keyboard */
    cbm_k_chkin(ASSET_LFN);
    while (n) {
        got = asset_macptr(MACPTR_N(n), p);
        if (!got)
            break;
        p += got;
        n -= got;
    }
    cbm_k_clrch();
    if (n)
        return 0;
    if (asset_progress)
        asset_progress(n0);
    return 1;
}
#else
unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    int got;
    unsigned char *p = (unsigned char *)dst;
    unsigned n0 = n;

    /* a read may return fewer bytes than asked even mid-file: go on until
     * n bytes are in, only a zero read is the end */
    while (n) {
        got = read(fd, p, n);
        if (got <= 0)
            return 0;
        p += got;
        n -= got;
    }
    if (asset_progress)
        asset_progress(n0);
    return 1;
}
#endif

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
#if defined(__CX16__)
    /* MACPTR straight into DATA0 (dst fixed), no bounce buffer */
    unsigned got;

    while (n) {
        cbm_k_chkin(ASSET_LFN);
        got = asset_macptr_fix(MACPTR_N(n), (void *)0x9F23);
        cbm_k_clrch();
        if (!got)
            return 0;
        n -= got;
        if (asset_progress)
            asset_progress(got);
    }
    return 1;
#else
    unsigned chunk;

    while (n) {
        chunk = n > ASSET_BUF_SIZE ? ASSET_BUF_SIZE : (unsigned)n;
        if (!asset_read(asset_buf, chunk))
            return 0;
        /* an IRQ callback may use the data ports, but it restores them
         * (vera_irq.h): the stream goes on where it was */
        vram_write(asset_buf, chunk);
        n -= chunk;
    }
    return 1;
#endif
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
