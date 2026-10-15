#ifndef __RMT_H__
#define __RMT_H__

/* rmt.h - RMT music on the VERA PSG, the same on every libvera host
 * (src/rmt: rmtplayr.s or lzsplayr.s, psgrmt.s, rmtdrv.s).
 *
 * The Atari RMT routine computes the POKEY registers in RAM and psgrmt.s
 * plays them on the VERA PSG, from the VERA frame clock (vera_irq.h).
 * RMT4 modules use PSG voices 0-3, RMT8 voices 0-7: voices 8-15 are free
 * for the sound effects.
 *
 * The module is linked in (tools/rmt2ca65.py, tools/sap2ca65.py: the
 * symbol rmt_song). */

extern const unsigned char rmt_song[];

/* Song frames a second (50: PAL Atari song, the default; 60: NTSC) and the
 * POKEY clock of its pitch (1: PAL, the default; 0: NTSC).  Set them before
 * rmt_init(). */
extern unsigned char rmt_rate;
extern unsigned char rmt_palnts;

/* Stop the music and init the player on a module; returns the instrument
 * speed (player calls per song frame, 1..4). */
unsigned char __fastcall__ rmt_init(const void *module);

/* Music on (installs the VERA frame clock if needed) / off (PSG voices
 * silent, the song position kept). */
void rmt_start(void);
void rmt_stop(void);

extern volatile unsigned int  rmt_frames;     /* song frames played */
extern unsigned char          rmt_ispeed;     /* player calls per song frame */
extern volatile unsigned char rmt_audc[];     /* AUDC values computed by the player */
extern volatile unsigned char rmt_pokey[16];  /* the POKEY registers (RAM) */

/* RMT_TRACKS = 4 (RMT4, mono: PSG voices 0-3) or 8 (RMT8, stereo for two
 * POKEYs: PSG voices 0-7) */
#ifndef RMT_TRACKS
#define RMT_TRACKS 4
#endif
extern const unsigned char rmt_tracks;                  /* tracks the player was built for */
void psg_silence(void);                                 /* PSG voices at volume 0 */
extern volatile unsigned char psg_enable;               /* 1 = voices follow the player */
extern volatile unsigned char psg_stereo;               /* 1 = stereo pan */
extern volatile unsigned char psg_volume[RMT_TRACKS];   /* VERA level of the voices (0..63) */

#endif
