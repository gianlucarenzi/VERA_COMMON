; ============================================================================
; plat_cx16.s - libvera host layer, Commander X16 (C interface: plat.h)
;
; The VERA is on the board at $9F20 and its VBLANK is also the KERNAL's IRQ
; (vera_irq.s chains a served VSYNC to it: plat.inc IRQ_OURS_END).  There is
; no second screen: hud.s does nothing on this host.
; ============================================================================

    .setcpu "65C02"

    .export _plat_joy, _plat_ntsc

JOYSTICK_GET    = $FF56                 ; A = joystick: A/X/Y = bytes 0/1/2

    .segment "DATA"

_plat_ntsc:     .byte 1                 ; the VERA's 60 Hz VGA frame

    .segment "CODE"

; ----------------------------------------------------------------------------
; unsigned char plat_joy(void): the keyboard joystick (KERNAL joystick 0) OR
; the SNES controller in port 1 (joystick 1), so either can play.
; KERNAL byte 0 (active low): B Y SEL STA UP DN LT RT; byte 1: A X L R 1111.
; ----------------------------------------------------------------------------
_plat_joy:
    lda #0
    jsr joyraw
    sta tmp2
    lda #1
    jsr joyraw
    ora tmp2                            ; B | A, up, down, left, right
    tax
    lda #0
    cpx #$80                            ; fire: B or A
    bcc :+
    lda #$10                            ; PAD_FIRE
:   sta tmp2
    txa
    and #$0F                            ; UP DN LT RT = bits 3 2 1 0
    tax
    lda dirs,x
    ora tmp2
    ldx #0
    rts

; A = KERNAL joystick -> A = active high: bit 7 B or A, bits 3-0 UP DN LT RT;
; 0 when the joystick is not present
joyraw:
    jsr JOYSTICK_GET
    cpy #0
    bne @none                           ; not present
    eor #$FF                            ; active high
    sta tmp
    txa
    eor #$FF
    and #$80                            ; A
    ora tmp
    and #$8F
    rts
@none:
    lda #0
    rts

    .segment "BSS"
tmp:    .res 1
tmp2:   .res 1

    .segment "RODATA"
; KERNAL bits UP=8 DN=4 LT=2 RT=1 -> PAD_UP=1 PAD_DOWN=2 PAD_LEFT=4 PAD_RIGHT=8
dirs:
    .repeat 16, I
    .byte ((I & 8) >> 3) | ((I & 4) >> 1) | ((I & 2) << 1) | ((I & 1) << 3)
    .endrepeat
