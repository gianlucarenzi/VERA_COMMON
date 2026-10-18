/*
 * vtext.c - a minimal text console on the VERA layer 1 (see vtext.h).
 */

#include "vmem.h"
#include "vtext.h"

extern const unsigned char vt_font[];   /* vtfont.s: 128 glyphs 8x8 */

unsigned char vt_cols, vt_rows, vt_top;
unsigned char vt_color = VT_COLOR;
static unsigned char tile_h;            /* 8 or 16 */
static unsigned char cur_x, cur_y;      /* cursor on the screen */

/* point DATA0 at column x of tilemap row r, increment 1 */
static void __fastcall__ set_cell(unsigned char x, unsigned char r)
{
    VERA_CTRL   = 0;
    VERA_ADDR_L = (unsigned char)(x << 1);
    VERA_ADDR_M = (unsigned char)(0xB0 + (r & (VT_MAP_ROWS - 1)));
    VERA_ADDR_H = VERA_INC1 | 1;
}

static void __fastcall__ clear_row(unsigned char r)
{
    unsigned char x;

    set_cell(0, r);
    for (x = vt_cols; x; --x) {
        VERA_DATA0 = 0x20;
        VERA_DATA0 = vt_color;
    }
}

static void set_vscroll(void)
{
    unsigned int v = (unsigned int)vt_top * tile_h;

    VERA_CTRL      = 0;
    VERA_L1_VSCR_L = (unsigned char)v;
    VERA_L1_VSCR_H = (unsigned char)(v >> 8);
}

void vt_clear(void)
{
    unsigned char r;

    for (r = 0; r < VT_MAP_ROWS; ++r)
        clear_row(r);
    vt_top = 0;
    cur_x = cur_y = 0;
    set_vscroll();
}

void __fastcall__ vt_init(unsigned char mode)
{
    unsigned int i;
    unsigned char b;

    tile_h  = (mode == VT_80X30) ? 16 : 8;
    vt_cols = (mode == VT_40X30) ? 40 : 80;
    vt_rows = (mode == VT_80X60) ? 60 : 30;

    VERA_CTRL      = 0;                         /* DCSEL 0 */
    b = VERA_DC_VIDEO;                          /* the other layers stay */
    if (!(b & 3))
        b |= VERA_VIDEO_VGA;
    VERA_DC_VIDEO  = (unsigned char)(b | VERA_VIDEO_LAYER1);
    VERA_DC_HSCALE = (mode == VT_40X30) ? 0x40 : 0x80;
    VERA_DC_VSCALE = VERA_DC_HSCALE;
    VERA_DC_BORDER = 0;
    VERA_L1_CONFIG   = 0x60;                    /* 128x64 tiles, 1 bpp text */
    VERA_L1_MAPBASE  = (unsigned char)(VT_MAP >> 9);
    VERA_L1_TILEBASE = (unsigned char)((VT_FONT >> 9) | (tile_h == 16 ? 2 : 0));
    VERA_L1_HSCR_L = 0;
    VERA_L1_HSCR_H = 0;

    vram_seek(VRAM(VT_FONT, VERA_INC1));
    if (tile_h == 8) {
        vram_write(vt_font, 128u * 8u);
    } else {
        for (i = 0; i < 128u * 8u; ++i) {       /* every row twice */
            b = vt_font[i];
            VERA_DATA0 = b;
            VERA_DATA0 = b;
        }
    }
    vt_clear();
}

void __fastcall__ vt_gotoxy(unsigned char x, unsigned char y)
{
    cur_x = x;
    cur_y = y;
}

static void newline(void)
{
    cur_x = 0;
    if (cur_y < vt_rows - 1) {
        ++cur_y;
        return;
    }
    /* scroll: the row below the screen becomes the new last row */
    clear_row((unsigned char)(vt_top + vt_rows));
    vt_top = (unsigned char)((vt_top + 1) & (VT_MAP_ROWS - 1));
    set_vscroll();
}

void __fastcall__ vt_glyph(unsigned char g)
{
    set_cell(cur_x, (unsigned char)(vt_top + cur_y));
    VERA_DATA0 = g & 0x7F;
    VERA_DATA0 = (g & 0x80) ? (unsigned char)((vt_color << 4) | (vt_color >> 4)) : vt_color;
    if (++cur_x >= vt_cols)
        newline();
}

void __fastcall__ vt_putc(char c)
{
    unsigned char a = (unsigned char)c;

    if (c == '\n') {
        newline();
        return;
    }
#if defined(__C64__) || defined(__CX16__)
    /* cc65 c64 / cx16 strings are PETSCII: back to ASCII */
    if (a >= 0x41 && a <= 0x5A)
        a += 0x20;                  /* a-z */
    else if (a >= 0xC1 && a <= 0xDA)
        a -= 0x80;                  /* A-Z */
#endif
    vt_glyph(a);
}

void __fastcall__ vt_puts(const char *s)
{
    while (*s)
        vt_putc(*s++);
}
