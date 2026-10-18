; ============================================================================
; hud.s - fast text on the host screen, the second monitor (C interface:
; hud.h).  Straight into the screen RAM of the host's text screen (ANTIC
; GRAPHICS 0 at SAVMSC on the Atari, the VIC-II screen at HIBASE on the C64),
; 40 columns, no cursor.  hud_u16 costs ~860 cycles for 2 digits and ~2000
; for 5 (cc65 C: ~4000); hud_bcd ~30 cycles a byte: keep scores in BCD.
; ============================================================================

    .setcpu "6502"
    .include "zeropage.inc"

    .export _hud_init, _hud_puts, _hud_u16, _hud_bcd, _bcd_add
    .import popa, popax

.ifdef __CX16__
; ----------------------------------------------------------------------------
; Commander X16: no second screen (its text screen is a VERA layer, the game
; uses it).  Under x16emu (detected by $9FBE/$9FBF = "16") the HUD goes to
; the emulator's stdout: hud_puts / hud_u16 / hud_bcd write into the KERNAL
; text screen in VRAM ($1B000, 256 bytes a row, char + colour), where the
; conio labels are too, and hud_flush prints the rows of it (40 x 25) that
; changed, at most once every 60 VERA frames (called by the writes, or
; directly).  On a real X16 they do nothing.  The VERA port 0 and CTRL are
; given back as found.
; ----------------------------------------------------------------------------
    .include "vera.inc"
    .import incsp2, incsp4, _vera_irq_count
    .export _hud_flush

EMU_ID1     = $9FBE                     ; x16emu: "1", "6"
EMU_ID2     = $9FBF
EMU_STDOUT  = $9FBB                     ; a byte written = a character on stdout
TXT_BANK    = $01                       ; KERNAL screen_addr = $1B000
TXT_PAGE    = $B0
ROWS        = 25
COLS        = 40
SC_ZERO     = $30

    .segment "BSS"

emu:        .res 1                      ; 1 = under x16emu
width:      .res 1
val:        .res 2
sv_ctrl:    .res 1
sv_l:       .res 1
sv_m:       .res 1
sv_h:       .res 1
last_flush: .res 1
row:        .res 1
sum:        .res 1
printed:    .res 1
row_sum:    .res ROWS

    .segment "RODATA"

p10_lo:     .byte <10000, <1000, <100, <10, <1
p10_hi:     .byte >10000, >1000, >100, >10, >1
hdr:        .byte "--- ", $48, $55, $44, " ---", $0A, 0   ; ASCII "HUD": ca65 -t cx16 strings are PETSCII

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

; save CTRL and the port 0 address, CTRL = 0
vsave:
    lda VERA_CTRL
    sta sv_ctrl
    lda #0
    sta VERA_CTRL
    lda VERA_ADDR_L
    sta sv_l
    lda VERA_ADDR_M
    sta sv_m
    lda VERA_ADDR_H
    sta sv_h
    rts

vrest:
    lda #0
    sta VERA_CTRL
    lda sv_l
    sta VERA_ADDR_L
    lda sv_m
    sta VERA_ADDR_M
    lda sv_h
    sta VERA_ADDR_H
    lda sv_ctrl
    sta VERA_CTRL
    rts

; port 0 at row A, column 0 of the text screen, step 2 (the chars)
seek_row:
    clc
    adc #TXT_PAGE
    sta VERA_ADDR_M
    lda #0
    sta VERA_ADDR_L
    lda #(VERA_INC2 | TXT_BANK)
    sta VERA_ADDR_H
    rts

; pop y then x (pushed x, y): port 0 at (x, y) of the text screen
locate:
    jsr popa
    jsr seek_row                        ; y
    jsr popa
    asl a                               ; x * 2
    sta VERA_ADDR_L
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
:   jsr vsave
    jsr locate
    ldy #0
@l: lda (ptr2),y
    beq @e
    jsr to_screen
    sta VERA_DATA0
    iny
    bne @l
@e: jsr vrest
    jmp auto_flush

_hud_u16:
    sta width
    lda emu
    bne :+
    jmp incsp4
:   jsr popax
    sta val
    stx val+1
    jsr vsave
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
    lda #$20                            ; space
    jmp @put
@show:
    lda #0
    sta tmp2
    lda tmp3
    ora #SC_ZERO
@put:
    sta VERA_DATA0
@next:
    inx
    cpx #5
    bne @digit
    jsr vrest
    jmp auto_flush

_hud_bcd:
    sta width                           ; bytes left
    lda emu
    bne :+
    jmp incsp4
:   jsr popax
    sta ptr2                            ; the BCD bytes
    stx ptr2+1
    jsr vsave
    jsr locate
    ldy #0
@b: lda (ptr2),y
    tax
    lsr a                               ; high digit
    lsr a
    lsr a
    lsr a
    ora #SC_ZERO
    sta VERA_DATA0
    txa                                 ; low digit
    and #$0F
    ora #SC_ZERO
    sta VERA_DATA0
    iny
    dec width
    bne @b
    jsr vrest
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
; void hud_flush(void): the rows of the text screen that changed, to stdout
; ----------------------------------------------------------------------------
_hud_flush:
    lda emu
    bne :+
    rts
:   lda _vera_irq_count
    sta last_flush
    jsr vsave
    lda #0
    sta printed
    sta row
@row:
    lda row                             ; checksum of the row
    jsr seek_row
    lda #0
    sta sum
    ldy #COLS
@s: lda sum
    asl a
    adc #0                              ; rotate left
    eor VERA_DATA0
    sta sum
    dey
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
    jsr seek_row
    ldy #COLS
@c: lda VERA_DATA0
    jsr to_ascii
    sta EMU_STDOUT
    dey
    bne @c
    lda #$0A
    sta EMU_STDOUT
@next:
    inc row
    lda row
    cmp #ROWS
    bne @row
    jmp vrest

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

row_lo:
    .repeat 25, I
    .byte <(I * 40)
    .endrepeat
row_hi:
    .repeat 25, I
    .byte >(I * 40)
    .endrepeat
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
.ifdef __ATARI__
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

    .segment "CODE"

; ----------------------------------------------------------------------------
; unsigned char __fastcall__ bcd_add(void *dst, const void *src,
;                                    unsigned char nbytes)
;   dst += src, nbytes packed BCD bytes, most significant first.  Returns 1
;   on overflow.  Decimal mode with interrupts off: the C64 KERNAL IRQ does
;   not clear D.
; ----------------------------------------------------------------------------
_bcd_add:
    sta tmp1
    jsr popax
    sta ptr2                            ; src
    stx ptr2+1
    jsr popax
    sta ptr1                            ; dst
    stx ptr1+1
    ldy tmp1
    dey
    php
    sei
    sed
    clc
@l: lda (ptr1),y
    adc (ptr2),y
    sta (ptr1),y
    dey
    bpl @l
    lda #0
    rol a                               ; A = carry out
    plp                                 ; D and I as before
    ldx #0
    rts
