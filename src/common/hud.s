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
