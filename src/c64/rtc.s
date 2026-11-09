; rtc.s - libvera, C64: plat_rtc (plat.h), a DS1307 on the user port.
;
; The DS1307 (I2C, address $D0) on the user port: SDA on PB0, SCL on PB1
; (CIA 2, $DD01 / $DD03), as the RTC adapters of the user port and VICE's
; "Userport RTC (DS1307)" (-userportdevice 17).  The lines are driven as
; open collector through the data direction register: a 0 is the line
; held low, an input the line let go (the pull-ups take it high).  Nothing
; else is touched: a missing chip does not answer its address (no ACK).
; Registers 0-6: seconds (bit 7: the clock halted), minutes, hours (24 h),
; day of the week, day, month, year (2 digits), in BCD.
;
; unsigned char __fastcall__ plat_rtc(struct sd_time *t): 1 = t set from
; the chip; 0 = no chip, or its clock halted (t not touched)

        .export _plat_rtc
        .macpack longbranch
        .importzp ptr1, tmp1, tmp2

PRB     = $DD01
DDRB    = $DD03
SDA     = $01
SCL     = $02

        .bss
regs:   .res 7
save_prb:  .res 1
save_ddrb: .res 1

        .code
_plat_rtc:
        sta ptr1
        stx ptr1+1
        php
        sei
        lda PRB
        sta save_prb
        lda DDRB
        sta save_ddrb
        lda PRB                         ; both lines written low when driven,
        and #<~(SDA | SCL)              ; let go (high) to start with
        sta PRB
        jsr sda_hi
        jsr scl_hi
        jsr start                       ; write the register pointer: 0
        lda #$D0
        jsr put
        jcs @none
        lda #0
        jsr put
        jcs @none
        jsr start                       ; repeated start, read 7 bytes
        lda #$D1
        jsr put
        jcs @none
        ldx #0
@rd:    jsr get
        sta regs,x
        inx
        cpx #7
        beq :+
        jsr ack
        jmp @rd
:       jsr nack
        jsr stop
        jsr restore
        plp
        lda regs                        ; the clock halted: no time
        bmi @no
        ldx #6                          ; BCD -> binary, checked
@bin:   cpx #3                          ; (the day of the week: skipped)
        beq @next
        lda regs,x
        jsr bcd
        bcs @no
        cmp max,x
        bcs @no
        cmp min,x
        bcc @no
        sta regs,x
@next:  dex
        bpl @bin
        ldy #0
        lda regs+6                      ; year 20xx
        clc
        adc #<2000
        sta (ptr1),y
        iny
        lda #>2000
        adc #0
        sta (ptr1),y
        iny                             ; month, day, hour, minute, second
        lda regs+5
        sta (ptr1),y
        iny
        lda regs+4
        sta (ptr1),y
        iny
        lda regs+2
        sta (ptr1),y
        iny
        lda regs+1
        sta (ptr1),y
        iny
        lda regs+0
        sta (ptr1),y
        lda #1
        ldx #0
        rts
@none:  jsr stop
        jsr restore
        plp
@no:    lda #0
        tax
        rts

; A BCD (bits 7 and 6 of the seconds and hours dropped) -> binary, C = 1 bad
bcd:    and #$7F
        cpx #2                          ; hours: 24 h mode, bits 5-0
        bne :+
        and #$3F
:       sta tmp1
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

restore:
        lda save_prb
        sta PRB
        lda save_ddrb
        sta DDRB
        rts

; the lines: low = driven (DDR 1, the port bit is 0), high = let go
sda_lo: lda DDRB
        ora #SDA
        sta DDRB
        rts
sda_hi: lda DDRB
        and #<~SDA
        sta DDRB
        rts
scl_lo: lda DDRB
        ora #SCL
        sta DDRB
        rts
scl_hi: lda DDRB
        and #<~SCL
        sta DDRB
        rts

start:  jsr sda_hi                      ; (a repeated start too)
        jsr scl_hi
        jsr sda_lo
        jmp scl_lo
stop:   jsr sda_lo
        jsr scl_hi
        jmp sda_hi

; A out, MSB first; C = 1: no ACK
put:    sta tmp1
        ldy #8
@bit:   asl tmp1
        bcc :+
        jsr sda_hi
        jmp @clk
:       jsr sda_lo
@clk:   jsr scl_hi
        jsr scl_lo
        dey
        bne @bit
        jsr sda_hi                      ; the ACK: the chip pulls SDA low
        jsr scl_hi
        lda PRB
        lsr a                           ; C = SDA
        php
        jsr scl_lo
        plp
        rts

; a byte in, MSB first
get:    jsr sda_hi
        ldy #8
@bit:   jsr scl_hi
        lda PRB
        lsr a                           ; C = SDA
        rol tmp1
        jsr scl_lo
        dey
        bne @bit
        lda tmp1
        rts

ack:    jsr sda_lo
        jsr scl_hi
        jsr scl_lo
        jmp sda_hi
nack:   jsr sda_hi
        jsr scl_hi
        jmp scl_lo

; the limits of seconds, minutes, hours, -, day, month, year
min:    .byte   0, 0, 0, 0, 1, 1, 0
max:    .byte   60, 60, 24, 8, 32, 13, 100
