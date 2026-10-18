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
 * speed (player calls per song frame, 1..4).  rmt_init: the music on the
 * VERA PSG; rmt_init_host: on the host's own chip (POKEY on the Atari, the
 * SID on the C64; not on the X16), without linking the PSG code. */
unsigned char __fastcall__ rmt_init(const void *module);
unsigned char __fastcall__ rmt_init_host(const void *module);

/* Music on (installs the VERA frame clock if needed) / off (PSG voices
 * silent, the song position kept). */
void rmt_start(void);
void rmt_stop(void);

/* C64: an RMT song made into a SID register stream at build time
 * (tools/rmt2sid.py, a .sds file: PAL and NTSC versions): the C64 only
 * writes SID registers, ~1000 cycles a frame instead of ~1500 (PSG) or
 * ~2200 (rmt_init_host, the translation on the C64).  The data (loaded by
 * the program, e.g. asset_load) must stay in memory while it plays; 1 = ok,
 * 0 = not an .sds file.  rmt_start / rmt_stop as for the other players. */
unsigned char __fastcall__ rmt_init_sds(const void *sds);
/* C64: 1 on an NTSC machine (choose the NTSC .sds), 0 on PAL */
unsigned char rmt_c64_ntsc(void);

/* Switch the output while the music plays: the VERA PSG (rmt_out_psg) or
 * the host's own chip (rmt_out_host).  The tempo is the VERA frame clock
 * either way.  POKEY: during SIO only
 * channels 1+2 play (3+4 are the serial clock); the SID has 3 voices, the
 * louder of POKEY channels 3 and 4 is heard. */
void rmt_out_psg(void);
void rmt_out_host(void);

/* Atari, POKEY output: bracket the transfers of an SIO driver that does not
 * set CRITIC (sio.s does it itself; the OS SIO sets CRITIC). */
void rmt_io_begin(void);
void rmt_io_end(void);

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
