; ============================================================================
; bcd.s - packed BCD addition (C interface: hud.h), its own module: a game
; that keeps scores in BCD without the HUD (the X16 game HUD) does not link
; hud.o and its 1 KB buffer.
; ============================================================================

    .setcpu "6502"
    .include "zeropage.inc"

    .export _bcd_add
    .import popax

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
