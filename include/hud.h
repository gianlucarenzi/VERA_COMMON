#ifndef HUD_H
#define HUD_H

/*
 * hud.h - fast text on the host screen, the second monitor (score, map,
 * status) (src/common/hud.s).
 *
 * Writes the character codes straight into the screen RAM of the host's
 * own text screen (ANTIC GRAPHICS 0 at SAVMSC on the Atari, the VIC-II
 * screen on the C64), 40 columns, no cursor, no scrolling: a few hundred
 * cycles a call where conio's cprintf takes most of a frame on the C64:
 * hud_u16 ~860 cycles for 2 digits, ~2000 for 5; hud_bcd ~30 a byte.
 * Use conio (clrscr, cputs) for the static text and these in the game loop.
 * Strings are as in the C source: ASCII on the Atari, PETSCII on the C64.
 *
 * Commander X16: no second screen; under x16emu the HUD (the KERNAL text
 * screen, conio labels included) goes to stdout (hud_flush), on a real X16
 * these do nothing.
 */

#define HUD_COLS 40

/* Find the screen RAM; after clrscr() or any change of screen. */
void hud_init(void);

/* Commander X16 under x16emu: the text screen rows that changed since the
 * last time, to the emulator's stdout (the writes below also call it, at
 * most once every 60 VERA frames).  Elsewhere it does nothing: the host
 * screen is the HUD. */
void hud_flush(void);

void __fastcall__ hud_puts(unsigned char x, unsigned char y, const char *s);

/* v right aligned in width columns (1-5), leading spaces. */
void __fastcall__ hud_u16(unsigned char x, unsigned char y, unsigned v, unsigned char width);

/* nbytes packed BCD bytes (most significant first), 2 digits each, leading
 * zeros shown: the score.  Keep scores in BCD, it is the cheap way. */
void __fastcall__ hud_bcd(unsigned char x, unsigned char y, const void *bcd,
                          unsigned char nbytes);

/* dst += src, nbytes packed BCD bytes (most significant first); returns 1
 * on overflow.  {0x00,0x01,0x00} is 100. */
unsigned char __fastcall__ bcd_add(void *dst, const void *src, unsigned char nbytes);

#endif /* HUD_H */
