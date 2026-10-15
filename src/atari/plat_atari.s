; ============================================================================
; plat_atari.s - libvera host layer, Atari XL/XE (C interface: plat.h)
; ============================================================================

    .setcpu "6502"
    .include "atari.inc"

    .export _plat_joy, _plat_ntsc

    .constructor plat_startup

    .segment "DATA"

; set by the constructor, before cc65 clears the BSS: not in BSS
_plat_ntsc:     .byte 0

    .segment "ONCE"

; PAL / NTSC from GTIA (PAL register bits 3:1: 000 = PAL, 111 = NTSC)
plat_startup:
    lda PAL
    and #$0E
    beq @pal
    lda #1
    sta _plat_ntsc
@pal:
    rts

    .segment "CODE"

; ----------------------------------------------------------------------------
; unsigned char plat_joy(void): stick 0 from PORTA bits 3:0 (active low),
; fire from TRIG0 (0 = pressed)
; ----------------------------------------------------------------------------
_plat_joy:
    lda PORTA
    and #$0F
    eor #$0F
    ldx TRIG0
    bne @nofire
    ora #$10
@nofire:
    ldx #0
    rts
