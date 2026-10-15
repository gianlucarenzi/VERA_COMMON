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

#if defined(__C64__)
#include <cbm.h>
#endif

unsigned char asset_buf[ASSET_BUF_SIZE];

static int fd = -1;

#if defined(__ATARI__)
static char path[2 + 12 + 1] = "D:";
#endif

unsigned char __fastcall__ asset_open(const char *name)
{
#if defined(__ATARI__)
    unsigned char i;
    char c;
#endif

    asset_close();
#if defined(__ATARI__)
    /* "D:" + the name in upper case */
    for (i = 0; i < 12 && (c = name[i]) != 0; ++i)
        path[2 + i] = (c >= 'a' && c <= 'z') ? (char)(c - 0x20) : c;
    path[2 + i] = 0;
    fd = open(path, O_RDONLY);
#else
    /* the build writes the files as PRG (c1541 -write) */
    _filetype = 'p';
    fd = open(name, O_RDONLY);
#endif
    return fd >= 0;
}

void asset_close(void)
{
    if (fd >= 0) {
        close(fd);
        fd = -1;
    }
}

unsigned char __fastcall__ asset_read(void *dst, unsigned n)
{
    int got;
    unsigned char *p = (unsigned char *)dst;

    /* a read may return fewer bytes than asked even mid-file: go on until
     * n bytes are in, only a zero read is the end */
    while (n) {
        got = read(fd, p, n);
        if (got <= 0)
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
