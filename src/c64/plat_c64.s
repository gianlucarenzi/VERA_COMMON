; ============================================================================
; plat_c64.s - libvera host layer, Commodore 64 (C interface: plat.h)
;
; The zero page of cfg/c64.cfg is $02-$8F, not cc65's $02-$1B: libvera
; (vtm_player.s, the RMT player) and the game use the BASIC area too.
; cc65 gives back only its own $02-$1B at exit; this module saves $1C-$8F
; at start-up and gives it back at exit, so BASIC finds its pointers again.
; ============================================================================

    .setcpu "6502"

    .export _plat_joy, _plat_ntsc

    .constructor plat_startup, 30       ; before the others: nothing in ZP yet
    .destructor plat_exit, 1            ; after the others

ZP_FIRST    = $1C
ZP_LAST     = $8F
ZP_SIZE     = ZP_LAST - ZP_FIRST + 1

VIC_CTRL1   = $D011
VIC_RASTER  = $D012
CIA1_PRA    = $DC00                     ; port 2 joystick, active low
CARD_SEL    = $DFFD                     ; VERA Module RBL-C64: select latch

    .segment "DATA"

; set by the constructor, before cc65 clears the BSS: not in BSS
_plat_ntsc:     .byte 0
zp_saved:       .res ZP_SIZE

    .segment "ONCE"

plat_startup:
    ldx #ZP_SIZE-1
@s: lda ZP_FIRST,x
    sta zp_saved,x
    dex
    bpl @s
    ; the RBL-C64 card answers (VERA at $DF00, GeoRAM) only while selected:
    ; any non-zero value in its latch.  Harmless elsewhere (VICE: a GeoRAM
    ; register mirror; a card in IO1 at $DE00 leaves IO2 free)
    lda #1
    sta CARD_SEL
    ; PAL / NTSC: the low byte of the last raster line is $37 on PAL
    ; (312 lines), $05 / $06 on NTSC (262 / 263 lines)
    php
    sei
@l1:
    lda VIC_RASTER
@l2:
    cmp VIC_RASTER
    beq @l2
    bmi @l1
    plp
    cmp #$20
    bcs @pal
    lda #1
    sta _plat_ntsc
@pal:
    rts

    .segment "CODE"

plat_exit:
    ldx #ZP_SIZE-1
@r: lda zp_saved,x
    sta ZP_FIRST,x
    dex
    bpl @r
    rts

; ----------------------------------------------------------------------------
; unsigned char plat_joy(void): port 2, bits 4:0 active low
; ----------------------------------------------------------------------------
_plat_joy:
    lda CIA1_PRA
    eor #$FF
    and #$1F
    ldx #0
    rts
