#ifndef PLAT_H
#define PLAT_H

/*
 * plat.h - the host differences seen by C code (src/atari, src/c64,
 * src/cx16).
 *
 * The VERA is the same chip on every host: the game sees only this small
 * interface for what is not the VERA.
 *
 * The host's own screen (ANTIC on the Atari, VIC-II on the C64) stays on:
 * it is the second monitor (score, map, status).  Write it with cc65 conio
 * (gotoxy, cputs, cprintf): 40 columns on both, the same source.
 *
 * Commander X16: no second screen (its text screen is a VERA layer too):
 * conio writes go to the KERNAL screen, hud.h does nothing.
 *
 * Apple IIe: the 40-column text page 1 is the second screen.  cc65 conio
 * switches the ROM in for a moment (VTABZ): the language card RAM ($D000-,
 * cfg/apple2.cfg LCCODE/LCRODATA, read only) must not be in use then.
 */

/* plat_joy(): the joystick, active high (Atari stick 0, C64 port 2, X16
 * joystick 0 = the keyboard joystick of the KERNAL, fire = B or A; Apple IIe:
 * the arrow keys or the joystick read at two thresholds, fire = space or
 * either Apple key / joystick button: a held arrow and space cannot both
 * be seen, the Apple keys can) */
#define PAD_UP     0x01
#define PAD_DOWN   0x02
#define PAD_LEFT   0x04
#define PAD_RIGHT  0x08
#define PAD_FIRE   0x10

unsigned char plat_joy(void);

#if defined(__APPLE2__)
/* Apple IIe: 1 = plat_joy reads the analog joystick too (~2100 cycles a
 * call, mostly waiting for its timers); 0 (default) = keyboard and buttons.
 * plat_joy reads $C010, which clears the keyboard strobe: kbhit()/cgetc()
 * see no key while it is called every frame. */
extern unsigned char plat_joy_analog;
#endif

/* 1 = NTSC host (60 Hz), 0 = PAL (50 Hz).  Information only: libvera
 * times everything on the VERA frame (vera_irq.h). */
extern unsigned char plat_ntsc;

#if defined(__ATARI__)
/* Atari XL/XE: the OS ROM copied into the RAM under it, ROM off (src/atari/
 * osram.s); then its character set at $E000 can be replaced in place.
 * 1 = done (or already RAM), 0 = no RAM under the OS. */
unsigned char os_ram(void);
#endif

/* Key that leaves a program (cgetc() code) and the name of the host. */
#if defined(__ATARI__)
#define PLAT_KEY_EXIT  0x1B             /* ESC */
#define PLAT_NAME      "Atari XL/XE"
#elif defined(__CX16__)
#define PLAT_KEY_EXIT  0x03             /* RUN/STOP */
#define PLAT_NAME      "Commander X16"
#elif defined(__APPLE2__)
#define PLAT_KEY_EXIT  0x1B             /* ESC */
#define PLAT_NAME      "Apple IIe"
#else
#define PLAT_KEY_EXIT  0x03             /* RUN/STOP */
#define PLAT_NAME      "C64"
#endif

#endif /* PLAT_H */
