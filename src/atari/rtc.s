; rtc.s - libvera, Atari: plat_rtc (plat.h), the ICD R-Time 8 cartridge.
;
; The R-Time 8 answers at $D5B8 (and $D5B9): a register number written
; there, then two reads give its value in BCD, the high nibble first.
; Registers 0-5: seconds, minutes, hours, day, month, year (2 digits).
; Without the cartridge the reads are the floating bus: the values are
; checked (BCD digits, in range), so a missing one is seen as missing.
; atari800 emulates it (-rtime, on by default).
;
; unsigned char __fastcall__ plat_rtc(struct sd_time *t): 1 = t set from
; the cartridge; 0 = no cartridge (t not touched)

        .export _plat_rtc
        .importzp ptr1, tmp1

RTIME   = $D5B8

        .bss
regs:   .res 6                          ; seconds, minutes, hours, day, month, year (binary)

        .code
_plat_rtc:
        sta ptr1
        stx ptr1+1
        ldx #5
@reg:   stx RTIME                       ; the register
        lda RTIME                       ; high digit
        and #$0F
        cmp #10
        bcs @no
        sta tmp1                        ; * 10
        asl a
        asl a
        adc tmp1
        asl a
        sta tmp1
        lda RTIME                       ; low digit
        and #$0F
        cmp #10
        bcs @no
        adc tmp1
        cmp max,x                       ; in range
        bcs @no
        cmp min,x
        bcc @no
        sta regs,x
        dex
        bpl @reg
        ldy #0                          ; year: 80-99 -> 19xx, else 20xx
        lda regs+5
        cmp #80
        lda #<1900
        ldx #>1900
        bcs :+
        lda #<2000
        ldx #>2000
:       clc
        adc regs+5
        sta (ptr1),y                    ; struct sd_time: year (2 bytes),
        iny                             ; month, day, hour, minute, second
        txa
        adc #0
        sta (ptr1),y
        ldx #4
@copy:  iny
        lda regs,x
        sta (ptr1),y
        dex
        bpl @copy
        lda #1
        ldx #0
        rts
@no:    lda #0
        tax
        rts

; the limits of seconds, minutes, hours, day, month, year
min:    .byte   0, 0, 0, 1, 1, 0
max:    .byte   60, 60, 24, 32, 13, 100
