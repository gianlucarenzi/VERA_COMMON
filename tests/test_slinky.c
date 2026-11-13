/* test_slinky.c - Apple II: the Slinky RAM card driver (slinky.h).
 *
 * Finds a VERA Module RBL-A2 (slinky_find), else uses the card in slot
 * SLINKY_SLOT (default 5: a2run --xmem 512 --xmem-slot 5), then checks:
 *   1. the size (RBL-A2: 4 = 256 KB);
 *   2. slinky_open puts back what its size test touched;
 *   3. a block written across a 64 KB boundary reads back the same
 *      (whole pages + a tail);
 *   4. the address wraps at the size (the same block one size higher).
 * Result on the text page: "SLINKY PASS" or "SLINKY FAIL <step>".
 *
 *   make PLATFORM=apple2 test-slinky
 *   a2run --model iie --vera-card rbl --frames 200 --text build/apple2/slinky.dsk
 *   a2run --model iie --xmem 512 --xmem-slot 5 --frames 200 --text build/apple2/slinky.dsk
 */
#include <conio.h>
#include <string.h>
#include "slinky.h"

#ifndef SLINKY_SLOT
#define SLINKY_SLOT 5
#endif

#define N    600u                       /* 2 pages + 88 bytes */
#define ADR  0x1FF80ul                  /* across the 128 KB boundary */

static unsigned char a[N], b[N], keep[4], keep2[4];

static void corners(unsigned char *k)
{
    unsigned char i;
    for (i = 0; i < 4; ++i) {
        slinky_seek((unsigned long)i << 16);
        slinky_read(k + i, 1);
    }
}

static unsigned char test(void)
{
    unsigned char slot, size;
    unsigned i;

    slot = slinky_find();
    cprintf("RBL-A2 SLOT %u\r\n", slot);
    if (!slot) slot = SLINKY_SLOT;
    size = slinky_open(slot);
    cprintf("SLOT %u SIZE %u X 64K\r\n", slot, size);
    if (!size) return 1;
    corners(keep);
    slinky_open(slot);
    corners(keep2);
    if (memcmp(keep, keep2, size < 4 ? size : 4)) return 2;
    for (i = 0; i < N; ++i) a[i] = (unsigned char)(i * 7 + (i >> 8));
    slinky_seek(ADR);
    slinky_write(a, N);
    slinky_seek(ADR);
    slinky_read(b, N);
    if (memcmp(a, b, N)) return 3;
    if (size < 16) {
        memset(b, 0, N);
        slinky_seek(ADR + ((unsigned long)size << 16));
        slinky_read(b, N);
        if (memcmp(a, b, N)) return 4;
    }
    return 0;
}

int main(void)
{
    unsigned char r;
    clrscr();
    r = test();
    if (r) cprintf("SLINKY FAIL %u\r\n", r);
    else cputs("SLINKY PASS\r\n");
    for (;;) ;
}
