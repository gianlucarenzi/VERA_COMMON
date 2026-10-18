/* vbm.c - a VBM2 full screen bitmap on the VERA (see vbm.h).
 *
 * VBM2: "VBM2", width(2), height(2), bpp(1), name_len(1), reserved(2),
 * name, palette (512), pixels (320 x 240).  The pixels are streamed to VRAM
 * a chunk at a time (asset_vram): 77 KB never pass through host RAM at once.
 * The palette goes to VRAM last, so the screen on display keeps its colours
 * until the whole image is in.
 */

#include <stdlib.h>

#include "vmem.h"
#include "asset.h"
#include "vbm.h"

#define HEADER_SIZE  12u
#define NAME_MAX     40u            /* longer names are skipped, not shown */
#define PALETTE_SIZE 512u
#define PIXEL_SIZE   (320ul * 240ul)
#define CHUNK        2048u          /* progress granularity */

static unsigned char saved_video, saved_hscale, saved_vscale;

/* Commander X16 default palette, entries 0-15 */
static const unsigned char default_palette16[32] = {
    0x00,0x00, 0xFF,0x0F, 0x00,0x08, 0xFE,0x0A, 0x4C,0x0C, 0xC5,0x00, 0x0A,0x00, 0xE7,0x0E,
    0x85,0x0D, 0x40,0x06, 0x77,0x0F, 0x33,0x03, 0x77,0x07, 0xF6,0x0A, 0x8F,0x00, 0xBB,0x0B
};

void vbm_init(void)
{
    VERA_CTRL = 0;
    saved_video  = VERA_DC_VIDEO;
    saved_hscale = VERA_DC_HSCALE;
    saved_vscale = VERA_DC_VSCALE;

    VERA_L0_CONFIG   = 0x07;        /* bitmap, 8 bpp */
    VERA_L0_TILEBASE = 0x00;        /* $00000, 320 wide */
    VERA_L0_HSCR_H   = 0;           /* bitmap: palette offset 0 */
    VERA_DC_HSCALE   = 0x40;        /* 320x240 -> 640x480 */
    VERA_DC_VSCALE   = 0x40;
    VERA_DC_VIDEO    = (unsigned char)(((saved_video & 3) ? saved_video : (saved_video | VERA_VIDEO_VGA))
                                       | VERA_VIDEO_LAYER0);
}

void vbm_done(void)
{
    VERA_CTRL = 0;
    VERA_DC_VIDEO  = saved_video;
    VERA_DC_HSCALE = saved_hscale;
    VERA_DC_VSCALE = saved_vscale;
    vera_palette(0, default_palette16, 16);
}

static unsigned char stream(unsigned long n, unsigned long *loaded, unsigned long total,
                            const char *name, unsigned char name_len, vbm_progress_cb progress)
{
    unsigned chunk;

    while (n) {
        chunk = n > CHUNK ? CHUNK : (unsigned)n;
        if (!asset_vram(chunk))
            return 0;
        n -= chunk;
        *loaded += chunk;
        if (progress) {
            /* the callback may move port 0: on the X16 conio writes the
               KERNAL text screen through the VERA */
            unsigned char l, m, h;

            VERA_CTRL = 0;
            l = VERA_ADDR_L; m = VERA_ADDR_M; h = VERA_ADDR_H;
            progress(name, name_len, *loaded, total);
            VERA_CTRL = 0;
            VERA_ADDR_L = l; VERA_ADDR_M = m; VERA_ADDR_H = h;
        }
    }
    return 1;
}

unsigned char __fastcall__ vbm_load(const char *name, vbm_progress_cb progress)
{
    unsigned char hdr[HEADER_SIZE];
    char title[NAME_MAX];
    unsigned char name_len, shown;
    unsigned long loaded = 0;
    const unsigned long total = PALETTE_SIZE + PIXEL_SIZE;
    unsigned char ok = 0;
    unsigned char *pal = 0;

    if (!asset_open(name))
        return 0;
    if (!asset_read(hdr, HEADER_SIZE))
        goto out;
    /* "VBM2" in ASCII (not '...': PETSCII on the C64) */
    if (hdr[0] != 0x56 || hdr[1] != 0x42 || hdr[2] != 0x4D || hdr[3] != 0x32)
        goto out;

    name_len = hdr[9];
    shown = name_len > NAME_MAX ? NAME_MAX : name_len;
    if (!asset_read(title, shown) || !asset_skip(name_len - shown))
        goto out;
    if (progress)
        progress(title, shown, 0, total);

    /* the palette is written last: while the pixels stream into VRAM that
     * is not shown yet, the screen on display keeps its colours, and the
     * image appears whole.  Without 512 bytes of heap, the file order. */
    pal = malloc(PALETTE_SIZE);
    if (pal) {
        if (!asset_read(pal, PALETTE_SIZE))
            goto out;
        loaded = PALETTE_SIZE;
    } else {
        vram_seek(VRAM(VERA_PALETTE_BASE, VERA_INC1));
        if (!stream(PALETTE_SIZE, &loaded, total, title, shown, progress))
            goto out;
    }
    vram_seek(VRAM(0, VERA_INC1));
    ok = stream(PIXEL_SIZE, &loaded, total, title, shown, progress);
    if (ok && pal)
        vera_palette(0, pal, 256);
out:
    free(pal);
    asset_close();
    return ok;
}
