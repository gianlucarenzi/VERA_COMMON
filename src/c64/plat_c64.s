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
    ; imported by cfg/c64.cfg: this module (the VERA select latch, the zero
    ; page save) is in every program, also one that calls none of its functions
    .export __VERA_SELECT__: absolute = 1

    .constructor plat_startup, 30       ; before the others: nothing in ZP yet
    .destructor plat_exit, 1            ; after the others

ZP_FIRST    = $1C
ZP_LAST     = $8F
ZP_SIZE     = ZP_LAST - ZP_FIRST + 1

VIC_CTRL1   = $D011
VIC_RASTER  = $D012
CIA1_PRA    = $DC00                     ; port 2 joystick, active low
CARD_SEL    = $DFFD                     ; VERA Module RBL-C64: VERA select latch
.ifndef C64_CARD_SEL
C64_CARD_SEL = 1
.endif

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
    ; the VERA of the RBL-C64 card answers at $DF00-$DF1F only while
    ; selected: any non-zero value in its latch (VICE emulates it too).  The
    ; GeoRAM of the card is always active; its registers are decoded exactly
    ; at $DFFE/$DFFF, so the latch does not touch them.
    ; C64_CARD_SEL=0 (mk/libvera.mk): $DFFD left alone, VERA not selected
.if C64_CARD_SEL
    lda #1
    sta CARD_SEL
.endif
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
