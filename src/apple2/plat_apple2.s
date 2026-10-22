; ============================================================================
; plat_apple2.s - libvera host layer, Apple IIe (C interface: plat.h)
;
; A cc65 program booted by the a2emu-vera SDK boot sector (no DOS) runs with
; the language card RAM read enabled ($C080, crt0), so the 6502 takes its IRQ
; vector from $FFFE in that RAM.  cc65's crt0 puts there a jump that switches
; the ROM in and leaves it in: plat_irq_lc (vera_irq_install, plat.inc
; IRQ_HOST_INSTALL) points it at irq_entry instead, which does what the
; Monitor ROM does (A to $45, then JMP ($03FE)) without the ROM.  An IRQ
; while cc65 conio has the ROM in for a moment goes through the ROM to the
; same $03FE.  irq_entry and everything an IRQ runs stay in the main RAM.
;
; plat_joy: the IIe keyboard (the arrows, space = fire) and the two Apple
; keys / joystick buttons (fire); the analog joystick only with
; plat_joy_analog = 1: it is read at two thresholds (~1/4 and ~3/4 of its
; travel) and the second one is ~2100 cycles after the timer start, spent
; waiting.  The IIe keyboard has no matrix: $C000 holds the last key, $C010
; bit 7 tells that some key is down, so a held arrow and space cannot both
; be seen; the Apple keys can (a2emu: Alt and Ctrl).
; ============================================================================

    .setcpu "6502"

    .export _plat_joy, _plat_ntsc, _plat_joy_analog
    .export plat_irq_lc

    .constructor plat_startup, 30

KBD         = $C000                     ; bit 7 = a key was typed, bits 6-0 its code
KBDSTRB     = $C010                     ; read: bit 7 = a key is down now (IIe)
BUTN0       = $C061                     ; Open Apple / button 0, bit 7
BUTN1       = $C062                     ; Closed Apple / button 1, bit 7
PADDL0      = $C064                     ; bit 7 = 1 while the timer runs
PADDL1      = $C065
PTRIG       = $C070                     ; starts the four paddle timers
LC_ROM_WRAM = $C081                     ; twice: ROM read, LC RAM bank 2 write
LC_RAM_RO   = $C080                     ; LC RAM bank 2 read, no write
IRQ_VEC     = $FFFE                     ; in the language card RAM
USER_IRQ    = $03FE                     ; the Monitor's user IRQ vector
A_SAVE      = $45

KEY_LEFT    = $08
KEY_RIGHT   = $15
KEY_UP      = $0B
KEY_DOWN    = $0A
KEY_SPACE   = $20

PAD_UP      = $01
PAD_DOWN    = $02
PAD_LEFT    = $04
PAD_RIGHT   = $08
PAD_FIRE    = $10

    .segment "DATA"

_plat_ntsc:         .byte 1             ; the Apple IIe (US) and the VERA's 60 Hz
_plat_joy_analog:   .byte 0             ; 1 = read the analog joystick too

    .segment "ONCE"

; until vera_irq takes $03FE, an IRQ or BRK just returns; the Apple II
; leaves the reset with IRQs masked (the other hosts' OS unmasks them)
plat_startup:
    lda #<irq_none
    sta USER_IRQ
    lda #>irq_none
    sta USER_IRQ+1
    cli
    rts

    .segment "CODE"

; the 6502 IRQ vector (language card RAM) -> irq_entry; IRQs off
plat_irq_lc:
    bit LC_ROM_WRAM
    bit LC_ROM_WRAM
    lda #<irq_entry
    sta IRQ_VEC
    lda #>irq_entry
    sta IRQ_VEC+1
    bit LC_RAM_RO
    rts

; as the Monitor ROM: A in $45, P and PC on the stack, then the user vector
irq_entry:
    sta A_SAVE
    jmp (USER_IRQ)

irq_none:
    lda A_SAVE
    rti

; ----------------------------------------------------------------------------
; unsigned char plat_joy(void): PAD_* bits, active high
; ----------------------------------------------------------------------------
_plat_joy:
    lda #0
    sta bits
    lda KBDSTRB                         ; a key down now?
    bpl @buttons
    lda KBD                             ; the last key typed
    and #$7F
    ldx #4
@k: cmp keys,x
    beq @hit
    dex
    bpl @k
    bmi @buttons
@hit:
    lda pads,x
    sta bits
@buttons:
    lda BUTN0
    ora BUTN1
    bpl @analog
    lda bits
    ora #PAD_FIRE
    sta bits
@analog:
    lda _plat_joy_analog
    beq @done
    php                                 ; the timing below must not stretch
    sei
    lda PTRIG                           ; ~704 cycles: below 64 = left / up
    ldx #140
@w1:dex                                 ; 5 cycles a loop
    bne @w1
    lda PADDL0
    bmi :+
    lda bits
    ora #PAD_LEFT
    sta bits
:   lda PADDL1
    bmi :+
    lda bits
    ora #PAD_UP
    sta bits
:   ldx #0                              ; ~2112 cycles: above 192 = right / down
@w2:dex                                 ; 256 loops: 1280 cycles
    bne @w2
    ldx #24
@w3:dex
    bne @w3
    lda PADDL0
    bpl :+
    lda bits
    ora #PAD_RIGHT
    sta bits
:   lda PADDL1
    bpl :+
    lda bits
    ora #PAD_DOWN
    sta bits
:   plp
@done:
    lda bits
    ldx #0
    rts

    .segment "BSS"

bits:   .res 1

    .segment "RODATA"

keys:   .byte KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_SPACE
pads:   .byte PAD_LEFT, PAD_RIGHT, PAD_UP, PAD_DOWN, PAD_FIRE
