#ifndef __SFX_H__
#define __SFX_H__

/* sfx.h - sound effects on the VERA PSG, the same on every libvera host
 * (src/common/sfx.s).
 *
 * The effects are made at build time by tools/psgsfx.py (a bank: the frames
 * of PSG voice registers, one a VERA frame) and played from the VERA frame
 * clock, after the music: PSG voices 12-15, free with RMT4 / RMT8 music.
 * A free voice is taken, else the one that started first.  ~70 cycles a
 * frame per sounding voice, nothing when no effect sounds. */

/* Install the frame clock and use this bank (stays in memory). */
void __fastcall__ sfx_init(const void *bank);

/* Play effect id of the bank (0 .. count-1). */
void __fastcall__ sfx_play(unsigned char id);

/* Every effect off. */
void sfx_stop(void);

/* 1 while an effect sounds. */
unsigned char sfx_busy(void);

#endif
