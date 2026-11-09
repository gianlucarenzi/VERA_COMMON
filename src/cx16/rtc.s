; rtc.s - libvera, Commander X16: plat_rtc (plat.h), the clock on the board
; through the KERNAL (clock_get_date_time: r0L year - 1900, r0H month,
; r1L day, r1H hours, r2L minutes, r2H seconds).
;
; unsigned char __fastcall__ plat_rtc(struct sd_time *t): 1 = t set

        .export _plat_rtc
        .importzp ptr1

CLOCK_GET_DATE_TIME = $FF50
R0      = $02

        .code
_plat_rtc:
        sta ptr1
        stx ptr1+1
        jsr CLOCK_GET_DATE_TIME
        ldy #0
        lda R0                          ; year
        clc
        adc #<1900
        sta (ptr1),y
        iny
        lda #>1900
        adc #0
        sta (ptr1),y
        ldx #1                          ; month, day, hours, minutes, seconds
:       iny
        lda R0,x
        sta (ptr1),y
        inx
        cpx #6
        bne :-
        lda #1
        ldx #0
        rts
