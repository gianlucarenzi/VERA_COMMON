#ifndef VTEXT_H
#define VTEXT_H

/*
 * vtext.h - a minimal text console on the VERA layer 1 (src/common/vtext.c).
 *
 * Same layout as the Atari VERA.SYS driver: tilemap 128x64 at $1B000 (256
 * bytes per row), 128 glyphs at $1F000 in ATASCII order, colour byte $61.
 * The mode is chosen at run time:
 *   VT_40X30  8x8 font, 320x240 scaled 2x (the game resolution)
 *   VT_80X30  8x16 font (the 8x8 font with every row doubled)
 *   VT_80X60  8x8 font
 * Scrolling moves the layer (VSCROLL) over the 64 rows of the tilemap.
 * Strings are ASCII on every host: on the C64 vt_putc() turns cc65's
 * PETSCII back into ASCII.
 */

#define VT_40X30  4
#define VT_80X30  8
#define VT_80X60  6

#define VT_MAP         0x1B000ul    /* tilemap, 256 bytes per row */
#define VT_MAP_ROWS    64
#define VT_FONT        0x1F000ul    /* 128 glyphs */
#define VT_COLOR       0x61         /* bg 6 (blue), fg 1 (white) */

/* Set up layer 1 as text in mode VT_* (the other layers stay as they are),
 * load the font, clear the screen with vt_color. */
void __fastcall__ vt_init(unsigned char mode);

/* Clear the screen and home the cursor (scroll back to 0). */
void vt_clear(void);

/* Cursor position on the screen. */
void __fastcall__ vt_gotoxy(unsigned char x, unsigned char y);

/* Colour byte of the following characters (bg << 4 | fg). */
extern unsigned char vt_color;

/* Put glyph g literally (bit 7: inverse video) and advance the cursor. */
void __fastcall__ vt_glyph(unsigned char g);

/* Print a character or string; '\n' starts a new line. */
void __fastcall__ vt_putc(char c);
void __fastcall__ vt_puts(const char *s);

/* Screen size of the current mode; first tilemap row of the screen. */
extern unsigned char vt_cols, vt_rows, vt_top;

#endif /* VTEXT_H */
