; ============================================================================
; hud.s - fast text on the host screen, the second monitor (C interface:
; hud.h).  Straight into the screen RAM of the host's text screen (ANTIC
; GRAPHICS 0 at SAVMSC on the Atari, the VIC-II screen at HIBASE on the C64,
; the text page 1 at $0400 on the Apple IIe),
; 40 columns, no cursor.  hud_u16 costs ~860 cycles for 2 digits and ~2000
; for 5 (cc65 C: ~4000); hud_bcd ~30 cycles a byte: keep scores in BCD.
; ============================================================================

    .setcpu "6502"
    .include "zeropage.inc"

    .export _hud_init, _hud_puts, _hud_u16, _hud_bcd
    .import popa, popax

.ifdef __CX16__
; ----------------------------------------------------------------------------
; Commander X16: no second screen (its text screen is a VERA layer, the game
; uses it).  Under x16emu (detected by $9FBE/$9FBF = "16") the HUD goes to
; the emulator's stdout (x16emu register $9FBB: a byte written = a character
; on stdout): hud_puts / hud_u16 / hud_bcd write screen codes into a 40 x 25
; buffer in RAM, and hud_flush prints the rows of it that changed, at most
; once every 60 VERA frames (called by the writes, or directly).  Nothing
; goes to VRAM: the KERNAL text screen area ($1B000-) is free for the game
; (it was the HUD's buffer until 2026-10-21).  On a real X16 they do nothing.
; ----------------------------------------------------------------------------
    .include "vera.inc"
    .import incsp2, incsp4, _vera_irq_count
    .export _hud_flush

EMU_ID1     = $9FBE                     ; x16emu: "1", "6"
EMU_ID2     = $9FBF
EMU_STDOUT  = $9FBB                     ; a byte written = a character on stdout
ROWS        = 25
COLS        = 40
SC_ZERO     = $30
SC_SPACE    = $20

    .segment "BSS"

emu:        .res 1                      ; 1 = under x16emu
width:      .res 1
val:        .res 2
last_flush: .res 1
row:        .res 1
sum:        .res 1
printed:    .res 1
outi:       .res 1                      ; column of the next character written
row_sum:    .res ROWS

    .segment "XBSS"                     ; banked RAM (cx16.cfg): the main RAM is
                                        ; short; hud_init fills it (not zeroed)
buf:        .res ROWS * COLS            ; screen codes

    .segment "RODATA"

p10_lo:     .byte <10000, <1000, <100, <10, <1
p10_hi:     .byte >10000, >1000, >100, >10, >1
hdr:        .byte "--- ", $48, $55, $44, " ---", $0A, 0   ; ASCII "HUD": ca65 -t cx16 strings are PETSCII
row_lo:     .repeat ROWS, I
            .byte <(buf + I * COLS)
            .endrepeat
row_hi:     .repeat ROWS, I
            .byte >(buf + I * COLS)
            .endrepeat

    .segment "CODE"

_hud_init:
    lda #0
    sta emu
    lda EMU_ID1
    cmp #'1'
    bne @r
    lda EMU_ID2
    cmp #'6'
    bne @r
    inc emu
    lda #<buf                           ; the buffer: spaces
    sta ptr3
    lda #>buf
    sta ptr3+1
    lda #SC_SPACE                       ; exactly ROWS * COLS bytes: whole
    ldy #0                              ; pages, then the rest (whole pages
    ldx #>(ROWS * COLS)                 ; ran 24 bytes past the buffer, into
@f: sta (ptr3),y                        ; the next module's BSS: sfx.s)
    iny
    bne @f
    inc ptr3+1
    dex
    bne @f
    ldy #<(ROWS * COLS)
@g: dey
    sta (ptr3),y
    bne @g
    ldx #ROWS-1                         ; every row printed the first time
    lda #$A5
@c: sta row_sum,x
    dex
    bpl @c
    lda _vera_irq_count
    sec
    sbc #60                             ; first flush at the first write
    sta last_flush
@r: rts

; ptr3 = buf + A * COLS (row A); preserves Y
row_ptr:
    tax
    lda row_lo,x
    sta ptr3
    lda row_hi,x
    sta ptr3+1
    rts

; pop y then x (pushed x, y): ptr3 = row y, outi = x
locate:
    jsr popa
    jsr row_ptr                         ; y
    jsr popa
    sta outi
    rts

; A -> buf[row][outi++]; preserves X, Y
out:
    sty val+1
    ldy outi
    sta (ptr3),y
    inc outi
    ldy val+1
    rts

; A = source character (PETSCII) -> screen code; preserves X, Y
to_screen:
    cmp #$C0
    bcc @lo
    and #$7F                            ; $C0-$DF -> $40-$5F
    rts
@lo:
    cmp #$40
    bcc @r
    cmp #$60
    bcs @r
    and #$1F                            ; $40-$5F -> $00-$1F
@r: rts

_hud_puts:
    sta ptr2
    stx ptr2+1
    lda emu
    bne :+
    jmp incsp2
:   jsr locate
    ldy #0
@l: lda (ptr2),y
    beq @e
    jsr to_screen
    jsr out
    iny
    bne @l
@e: jmp auto_flush

_hud_u16:
    sta width
    lda emu
    bne :+
    jmp incsp4
:   jsr popax
    sta val
    stx val+1
    jsr locate
    lda #1
    sta tmp2                            ; 1 = still in the leading zeros
    ldx #0                              ; power of ten
@digit:
    lda #0
    sta tmp3
@sub:                                   ; tmp3 = val / 10^(4-x), val %= it
    lda val
    cmp p10_lo,x
    lda val+1
    sbc p10_hi,x
    bcc @got
    sta val+1
    lda val
    sbc p10_lo,x                        ; C = 1
    sta val
    inc tmp3
    bne @sub
@got:
    txa                                 ; column shown when x >= 5 - width
    clc
    adc width
    cmp #5
    bcc @next
    lda tmp3
    bne @show
    cpx #4                              ; the units digit is always shown
    beq @show
    lda tmp2
    beq @show
    lda #SC_SPACE
    jmp @put
@show:
    lda #0
    sta tmp2
    lda tmp3
    ora #SC_ZERO
@put:
    ldy outi                            ; (out would clobber val+1)
    sta (ptr3),y
    inc outi
@next:
    inx
    cpx #5
    bne @digit
    jmp auto_flush

_hud_bcd:
    sta width                           ; bytes left
    lda emu
    bne :+
    jmp incsp4
:   jsr popax
    sta ptr2                            ; the BCD bytes
    stx ptr2+1
    jsr locate
    ldy #0
@b: lda (ptr2),y
    tax
    lsr a                               ; high digit
    lsr a
    lsr a
    lsr a
    ora #SC_ZERO
    jsr out
    txa                                 ; low digit
    and #$0F
    ora #SC_ZERO
    jsr out
    iny
    dec width
    bne @b
    jmp auto_flush

; hud_flush() if 60 VERA frames went by since the last one
auto_flush:
    lda _vera_irq_count
    sec
    sbc last_flush
    cmp #60
    bcs _hud_flush
    rts

; ----------------------------------------------------------------------------
; void hud_flush(void): the rows of the buffer that changed, to stdout
; ----------------------------------------------------------------------------
_hud_flush:
    lda emu
    bne :+
    rts
:   lda _vera_irq_count
    sta last_flush
    lda #0
    sta printed
    sta row
@row:
    lda row                             ; checksum of the row
    jsr row_ptr
    lda #0
    sta sum
    ldy #0
@s: lda sum
    asl a
    adc #0                              ; rotate left
    eor (ptr3),y
    sta sum
    iny
    cpy #COLS
    bne @s
    ldx row
    cmp row_sum,x
    beq @next
    sta row_sum,x
    lda printed                         ; first changed row: the header
    bne @line
    inc printed
    ldy #0
@h: lda hdr,y
    beq @line
    sta EMU_STDOUT
    iny
    bne @h
@line:
    lda row                             ; "rr " then the 40 characters
    ldx #'0'
@t: cmp #10
    bcc @u
    sbc #10                             ; C = 1
    inx
    bne @t
@u: stx EMU_STDOUT
    ora #'0'
    sta EMU_STDOUT
    lda #' '
    sta EMU_STDOUT
    lda row
    jsr row_ptr
    ldy #0
@c: lda (ptr3),y
    jsr to_ascii
    sta EMU_STDOUT
    iny
    cpy #COLS
    bne @c
    lda #$0A
    sta EMU_STDOUT
@next:
    inc row
    lda row
    cmp #ROWS
    bne @row
    rts

; screen code (bit 7 = reverse, ignored) -> ASCII
to_ascii:
    and #$7F
    cmp #$20
    bcs @hi
    cmp #$01                            ; $01-$1A: a-z (lower case set)
    bcc @at
    cmp #$1B
    bcs @dot
    adc #$60                            ; C = 0
    rts
@at:
    lda #'@'
    rts
@hi:
    cmp #$40
    bcc @r                              ; $20-$3F: as ASCII
    cmp #$41                            ; $41-$5A: A-Z
    bcc @dot
    cmp #$5B
    bcs @dot
@r: rts
@dot:
    lda #'.'
    rts

.else

.ifdef __ATARI__
SAVMSC      = $58
SC_SPACE    = $00                       ; ANTIC internal codes
SC_ZERO     = $10
.elseif .defined(__APPLE2__)
TEXT_PAGE1  = $0400                     ; 24 rows of 40, interleaved
SC_SPACE    = $A0                       ; normal characters: ASCII + $80
SC_ZERO     = $B0
.else
HIBASE      = $0288
SC_SPACE    = $20                       ; VIC-II screen codes
SC_ZERO     = $30
.endif

    .segment "BSS"

screen:     .res 2
width:      .res 1
val:        .res 2

    .segment "RODATA"

.ifdef __APPLE2__
; row r at (r & 7) * $80 + (r >> 3) * $28; a 25th row would be in the screen
; holes the slot cards use: it is row 23 again
row_lo:
    .repeat 25, I
    .byte <((((I < 24) * I + (I >= 24) * 23) & 7) * $80 + (((I < 24) * I + (I >= 24) * 23) >> 3) * $28)
    .endrepeat
row_hi:
    .repeat 25, I
    .byte >((((I < 24) * I + (I >= 24) * 23) & 7) * $80 + (((I < 24) * I + (I >= 24) * 23) >> 3) * $28)
    .endrepeat
.else
row_lo:
    .repeat 25, I
    .byte <(I * 40)
    .endrepeat
row_hi:
    .repeat 25, I
    .byte >(I * 40)
    .endrepeat
.endif
p10_lo:     .byte <10000, <1000, <100, <10, <1
p10_hi:     .byte >10000, >1000, >100, >10, >1

    .segment "CODE"

    .export _hud_flush

    .segment "CODE"

; hud_flush(): the host screen is already the HUD
_hud_flush:
    rts

; ----------------------------------------------------------------------------
; void hud_init(void)
; ----------------------------------------------------------------------------
_hud_init:
.ifdef __ATARI__
    lda SAVMSC
    sta screen
    lda SAVMSC+1
.elseif .defined(__APPLE2__)
    lda #<TEXT_PAGE1
    sta screen
    lda #>TEXT_PAGE1
.else
    lda #0
    sta screen
    lda HIBASE
.endif
    sta screen+1
    rts

; pop y then x (pushed x, y): ptr1 = screen + 40 * y + x
locate:
    jsr popa
    sta tmp2                            ; y
    jsr popa
    sta tmp1                            ; x
    ldy tmp2
    lda row_lo,y
    clc
    adc screen
    sta ptr1
    lda row_hi,y
    adc screen+1
    sta ptr1+1
    lda ptr1
    clc
    adc tmp1
    sta ptr1
    bcc @r
    inc ptr1+1
@r: rts

; A = source character -> screen code; preserves X, Y
to_screen:
.ifdef __APPLE2__
    ora #$80                            ; ASCII -> normal (IIe: lower case too)
    rts
.elseif .defined(__ATARI__)
    cmp #$20                            ; ATASCII -> internal
    bcs @hi
    adc #$40                            ; C = 0
    rts
@hi:
    cmp #$60
    bcs @r
    sec
    sbc #$20
@r: rts
.else
    cmp #$C0                            ; PETSCII -> screen code
    bcc @lo
    and #$7F                            ; $C0-$DF -> $40-$5F
    rts
@lo:
    cmp #$40
    bcc @r
    cmp #$60
    bcs @r
    and #$1F                            ; $40-$5F -> $00-$1F
@r: rts
.endif

; ----------------------------------------------------------------------------
; void __fastcall__ hud_puts(unsigned char x, unsigned char y, const char *s)
; ----------------------------------------------------------------------------
_hud_puts:
    sta ptr2
    stx ptr2+1
    jsr locate
    ldy #0
@l: lda (ptr2),y
    beq @r
    jsr to_screen
    sta (ptr1),y
    iny
    bne @l
@r: rts

; ----------------------------------------------------------------------------
; void __fastcall__ hud_u16(unsigned char x, unsigned char y, unsigned v,
;                           unsigned char width)
;   v right aligned in width (1-5) columns, leading spaces; the digits above
;   width are dropped (v modulo 10^width)
; ----------------------------------------------------------------------------
_hud_u16:
    sta width
    jsr popax
    sta val
    stx val+1
    jsr locate
    lda #1
    sta tmp2                            ; 1 = still in the leading zeros
    ldy #0                              ; output column
    ldx #0                              ; power of ten
@digit:
    lda #0
    sta tmp3
@sub:                                   ; tmp3 = val / 10^(4-x), val %= it
    lda val
    cmp p10_lo,x
    lda val+1
    sbc p10_hi,x
    bcc @got
    sta val+1
    lda val
    sbc p10_lo,x                        ; C = 1
    sta val
    inc tmp3
    bne @sub
@got:
    txa                                 ; column shown when x >= 5 - width
    clc
    adc width
    cmp #5
    bcc @next
    lda tmp3
    bne @show
    cpx #4                              ; the units digit is always shown
    beq @show
    lda tmp2
    beq @show
    lda #SC_SPACE
    jmp @put
@show:
    lda #0
    sta tmp2
    lda tmp3
    ora #SC_ZERO
@put:
    sta (ptr1),y
    iny
@next:
    inx
    cpx #5
    bne @digit
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ hud_bcd(unsigned char x, unsigned char y,
;                           const void *bcd, unsigned char nbytes)
;   nbytes packed BCD bytes, most significant first, 2 digits each, leading
;   zeros shown (arcade score)
; ----------------------------------------------------------------------------
_hud_bcd:
    sta width                           ; bytes left
    jsr popax
    sta ptr2                            ; the BCD bytes
    stx ptr2+1
    jsr locate
    ldy #0                              ; output column
@b: sty tmp1
    ldy #0
    lda (ptr2),y
    ldy tmp1
    tax
    lsr a                               ; high digit
    lsr a
    lsr a
    lsr a
    ora #SC_ZERO
    sta (ptr1),y
    iny
    txa                                 ; low digit
    and #$0F
    ora #SC_ZERO
    sta (ptr1),y
    iny
    inc ptr2
    bne @n
    inc ptr2+1
@n: dec width
    bne @b
    rts

.endif ; __CX16__
