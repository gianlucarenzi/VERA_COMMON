; vtfont.s - the font of vtext.c: 128 glyphs 8x8 in ATASCII order (ASCII
; for $20-$7E).  vt_init() doubles every row for the 8x16 mode.

    .export _vt_font

    .segment "RODATA"

_vt_font:
    .incbin "font8x8.bin"
