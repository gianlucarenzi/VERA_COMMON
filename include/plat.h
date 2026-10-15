#ifndef PLAT_H
#define PLAT_H

/*
 * plat.h - the host differences seen by C code (src/atari, src/c64).
 *
 * The VERA is the same chip on every host: the game sees only this small
 * interface for what is not the VERA.
 *
 * The host's own screen (ANTIC on the Atari, VIC-II on the C64) stays on:
 * it is the second monitor (score, map, status).  Write it with cc65 conio
 * (gotoxy, cputs, cprintf): 40 columns on both, the same source.
 */

/* plat_joy(): the joystick, active high (Atari stick 0, C64 port 2) */
#define PAD_UP     0x01
#define PAD_DOWN   0x02
#define PAD_LEFT   0x04
#define PAD_RIGHT  0x08
#define PAD_FIRE   0x10

unsigned char plat_joy(void);

/* 1 = NTSC host (60 Hz), 0 = PAL (50 Hz).  Information only: libvera
 * times everything on the VERA frame (vera_irq.h). */
extern unsigned char plat_ntsc;

/* Key that leaves a program (cgetc() code) and the name of the host. */
#if defined(__ATARI__)
#define PLAT_KEY_EXIT  0x1B             /* ESC */
#define PLAT_NAME      "Atari XL/XE"
#else
#define PLAT_KEY_EXIT  0x03             /* RUN/STOP */
#define PLAT_NAME      "C64"
#endif

#endif /* PLAT_H */
