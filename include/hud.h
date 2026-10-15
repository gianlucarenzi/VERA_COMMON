#ifndef HUD_H
#define HUD_H

/*
 * hud.h - fast text on the host screen, the second monitor (score, map,
 * status) (src/common/hud.c).
 *
 * Writes the character codes straight into the screen RAM of the host's
 * own text screen (ANTIC GRAPHICS 0 at SAVMSC on the Atari, the VIC-II
 * screen on the C64), 40 columns, no cursor, no scrolling: a few hundred
 * cycles a call where conio's cprintf takes most of a frame on the C64.
 * Use conio (clrscr, cputs) for the static text and these in the game loop.
 * Strings are as in the C source: ASCII on the Atari, PETSCII on the C64.
 */

#define HUD_COLS 40

/* Find the screen RAM; after clrscr() or any change of screen. */
void hud_init(void);

void __fastcall__ hud_puts(unsigned char x, unsigned char y, const char *s);

/* v right aligned in width columns (1-5), leading spaces. */
void __fastcall__ hud_u16(unsigned char x, unsigned char y, unsigned v, unsigned char width);

#endif /* HUD_H */
