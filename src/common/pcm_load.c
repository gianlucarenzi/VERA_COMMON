/* pcm_load.c - a .pcm sample (pcm.h) from the game's files to VRAM */

#include "asset.h"
#include "vmem.h"
#include "vera.h"
#include "pcm.h"

unsigned char __fastcall__ pcm_load(const char *name, unsigned long vram, pcm_sound *s)
{
    unsigned char hdr[3];
    unsigned char ok;

    if (!asset_open(name))
        return 0;
    ok = asset_read(hdr, 3);
    if (ok) {
        s->vram = vram;
        s->len = hdr[0] | (hdr[1] << 8);
        s->rate = hdr[2];
        vram_seek(VRAM(vram, VERA_INC1));
        ok = asset_vram(s->len);
    }
    asset_close();
    return ok;
}
