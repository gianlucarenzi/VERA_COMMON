; rtc.s - libvera, Apple IIe: plat_rtc (plat.h), a No-Slot Clock (Dallas
; DS1216E SmartWatch) under the CD ROM, seen through the internal ROM page
; $C300.
;
; The clock hides until it sees its 64-bit recognition pattern (C5 3A A3
; 5C C5 3A A3 5C, every byte LSB first) as the A0 of reads with A2 = 0
; ($C300 / $C301); then 64 reads with A2 = 1 ($C304) give its registers on
; D0, LSB first: hundredths, seconds, minutes, hours, day of the week (bit
; 4 = 1: oscillator stopped), date, month, year, in BCD.  A read of $C304
; first starts the pattern from its beginning.  The internal $C3 ROM is
; switched in for this (SETINTC3ROM) and the slot's one back if it was in.
; Without the clock the reads are the ROM's bytes: the values are checked
; (BCD digits, in range), so a missing clock is seen as missing.
; a2emu-vera emulates it (A2_NSC, A2_NSC_FILE: a clock that runs with the
; emulated machine and never goes back).
;
; unsigned char __fastcall__ plat_rtc(struct sd_time *t): 1 = t set from
; the clock; 0 = no clock, or stopped (t not touched)

        .export _plat_rtc
        .importzp ptr1, tmp1, tmp2

RDC3ROM     = $C017                     ; bit 7 = 1: the slot's $C3 ROM
SETINTC3ROM = $C00A
SETSLOTC3ROM = $C00B
NSC_W0      = $C300                     ; A2 = 0, A0 = 0: a 0 to the clock
NSC_W1      = $C301                     ; A2 = 0, A0 = 1: a 1
NSC_R       = $C304                     ; A2 = 1: a bit from the clock (D0)

        .bss
regs:   .res 8
slot:   .res 1

        .code
_plat_rtc:
        sta ptr1
        stx ptr1+1
        php
        sei
        lda RDC3ROM
        sta slot
        sta SETINTC3ROM
        lda NSC_R                       ; the pattern from its start
        ldx #0
@pat:   lda pattern,x
        sta tmp1
        ldy #8
@pbit:  lsr tmp1
        bcs :+
        lda NSC_W0
        jmp @pnext
:       lda NSC_W1
@pnext: dey
        bne @pbit
        inx
        cpx #8
        bne @pat
        ldx #0                          ; the 8 registers
@reg:   ldy #8
@rbit:  lda NSC_R
        lsr a                           ; D0 -> C
        ror tmp1                        ; LSB first: in from the top
        dey
        bne @rbit
        lda tmp1
        sta regs,x
        inx
        cpx #8
        bne @reg
        bit slot                        ; the slot's $C3 ROM back
        bpl :+
        sta SETSLOTC3ROM
:       plp
        lda regs+4                      ; oscillator stopped: no time
        and #$10
        bne @no
        ldx #7                          ; BCD -> binary, checked
@bin:   cpx #4                          ; (day of the week: skipped,
        beq @next                       ;  hundredths too)
        cpx #0
        beq @next
        lda regs,x
        cpx #3                          ; hours: 24 h, bits 5-0
        bne :+
        and #$3F
:       jsr bcd
        bcs @no
        cmp max,x
        bcs @no
        cmp min,x
        bcc @no
        sta regs,x
@next:  dex
        bpl @bin
        ldy #0                          ; year: 80-99 -> 19xx, else 20xx
        lda regs+7
        cmp #80
        lda #<1900
        ldx #>1900
        bcs :+
        lda #<2000
        ldx #>2000
:       clc
        adc regs+7
        sta (ptr1),y
        iny
        txa
        adc #0
        sta (ptr1),y
        iny                             ; month, day, hour, minute, second
        lda regs+6
        sta (ptr1),y
        iny
        lda regs+5
        sta (ptr1),y
        iny
        lda regs+3
        sta (ptr1),y
        iny
        lda regs+2
        sta (ptr1),y
        iny
        lda regs+1
        sta (ptr1),y
        lda #1
        ldx #0
        rts
@no:    lda #0
        tax
        rts

; A BCD -> binary; C = 1: not BCD
bcd:    sta tmp1
        and #$0F
        cmp #10
        bcs @bad
        sta tmp2
        lda tmp1
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #10
        bcs @bad
        sta tmp1                        ; * 10 + low
        asl a
        asl a
        adc tmp1
        asl a
        adc tmp2
        clc
        rts
@bad:   sec
        rts

pattern: .byte  $C5, $3A, $A3, $5C, $C5, $3A, $A3, $5C

; the limits of -, seconds, minutes, hours, -, date, month, year
min:    .byte   0, 0, 0, 0, 0, 1, 1, 0
max:    .byte   100, 60, 60, 24, 8, 32, 13, 100
