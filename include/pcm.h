#ifndef __PCM_H__
#define __PCM_H__

/* pcm.h - PCM samples on the VERA audio FIFO, the same on every libvera
 * host (src/common/pcm.s, pcm_load.c).
 *
 * A sample is kept in VRAM: pcm_load reads a .pcm file (asset.h: SD or
 * disk) straight to VRAM, no RAM buffer; pcm_play streams it from VRAM to
 * the FIFO from the VERA frame clock (~12 cycles a byte, ~1300 cycles a
 * frame at 6.1 kHz, only while it plays).  One sample at a time: a new
 * pcm_play cuts the one that plays.
 *
 * .pcm file (tools: RastanRIP voice_sfx.py): 2 bytes length (LE), 1 byte
 * AUDIO_RATE (rate = 48828 * AUDIO_RATE / 128 Hz, 16 = 6104 Hz), then the
 * samples, 8 bit signed. */

typedef struct {
    unsigned long vram;         /* where the samples are */
    unsigned len;               /* bytes */
    unsigned char rate;         /* AUDIO_RATE */
} pcm_sound;

/* Read a .pcm file to VRAM at vram and fill *s; 1 = ok. */
unsigned char __fastcall__ pcm_load(const char *name, unsigned long vram, pcm_sound *s);

void __fastcall__ pcm_play(const pcm_sound *s);
void pcm_stop(void);

/* 1 while the sample plays */
unsigned char pcm_busy(void);

#endif
