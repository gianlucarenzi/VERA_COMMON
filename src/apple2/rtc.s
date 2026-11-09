; rtc.s - libvera, Apple II: plat_rtc (plat.h).  No clock card or No-Slot
; Clock is read yet (a2emu emulates none: nothing to test one on), so the
; programs get the time set with sd_set_time, or 1980-01-01.
;
; unsigned char __fastcall__ plat_rtc(struct sd_time *t): 0 = no clock

        .export _plat_rtc

        .code
_plat_rtc:
        lda #0
        tax
        rts
