; ============================================================================
; plat_atari.s - libvera host layer, Atari XL/XE (C interface: plat.h)
;
; The VERA card is a PBI device: its registers ($D100-$D11F) answer only
; while its bit is set in $D1FF (Atari PBI rule).  The OS selects it only
; around its own PBI calls and deselects it after, so the program selects
; it for its whole run:
;   - start-up: the card's bit out of PDVMSK, so the OS no longer calls the
;     card in SIO, CIO and IRQ (its ROM handles none of them: the VERA IRQs
;     are taken by vera_irq.s) and does not deselect it; then the card
;     selected (SHPDVS and $D1FF).  Its ROM replaces the Math Pack at
;     $D800-$DFFF meanwhile: no floating point (cc65 does not use it).
;   - exit: PDVMSK back, the card deselected, the Math Pack back for DOS and
;     BASIC.
; Another PBI device makes the OS select it (and deselect everything) in
; SIO: plat_vera_select() selects the card again after such OS I/O.
; ============================================================================

    .setcpu "6502"
    .include "atari.inc"

    .export _plat_joy, _plat_ntsc, _plat_vera_select
    ; imported by cfg/atari*.cfg: this module (the card selection) is in
    ; every program, also one that calls none of its functions
    .export __VERA_SELECT__: absolute = 1

    .constructor plat_startup
    .destructor plat_exit

PBI_LATCH       = $D1FF                 ; PBI device select (write)
VERA_PBI_BIT    = $80                   ; the card's PBI device bit (ROM: $D803)

    .segment "DATA"

; set by the constructor, before cc65 clears the BSS: not in BSS
_plat_ntsc:     .byte 0
pdvmsk_saved:   .byte 0

    .segment "ONCE"

plat_startup:
    lda PDVMSK
    sta pdvmsk_saved
    and #<~VERA_PBI_BIT
    sta PDVMSK
    jsr _plat_vera_select
; PAL / NTSC from GTIA (PAL register bits 3:1: 000 = PAL, 111 = NTSC)
    lda PAL
    and #$0E
    beq @pal
    lda #1
    sta _plat_ntsc
@pal:
    rts

    .segment "CODE"

; ----------------------------------------------------------------------------
; void plat_vera_select(void): the card selected ($D1FF and its OS shadow)
; ----------------------------------------------------------------------------
_plat_vera_select:
    lda #VERA_PBI_BIT
    sta SHPDVS
    sta PBI_LATCH
    rts

; at exit: the OS sees the card again, the Math Pack is back
plat_exit:
    lda pdvmsk_saved
    sta PDVMSK
    lda #0
    sta SHPDVS
    sta PBI_LATCH
    rts

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
