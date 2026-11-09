; sdtime.s - libvera: the date and time of the files written on the SD
; (sdfs.h: sd_set_time, sd_get_time).
;
; Every file or directory made (sd_create, sd_mkdir: src/fat32/sdfsw.s)
; gets, in this order: the time of an RTC adapter (plat_rtc: the R-Time 8 on
; the Atari, a DS1307 on the C64's user port, the X16's own clock), else the
; one the program set with sd_set_time, else 1980-01-01 00:00:00, the first
; date FAT has.  In the main RAM: the Atari's FAT32 code calls it from its
; RAMbo bank.

        .export _sd_set_time, _sd_get_time, sd_time_fat
        .import _plat_rtc, fat32_time_year
        .importzp ptr2

TIME_SIZE = 7                           ; struct sd_time

        .data
set:    .byte   0                       ; sd_set_time called
user:   .word   1980                    ; its time; before it the first date
        .byte   1, 1, 0, 0, 0

        .bss
now:    .res    TIME_SIZE

        .code

; void __fastcall__ sd_set_time(const struct sd_time *t)
_sd_set_time:
        sta ptr2
        stx ptr2+1
        ldy #TIME_SIZE - 1
:       lda (ptr2),y
        sta user,y
        dey
        bpl :-
        lda #1
        sta set
        rts

; unsigned char __fastcall__ sd_get_time(struct sd_time *t): the time the
; next file gets; 1 = from an RTC adapter
_sd_get_time:
        sta ptr2
        stx ptr2+1
        jsr fill
        pha
        ldy #TIME_SIZE - 1
:       lda now,y
        sta (ptr2),y
        dey
        bpl :-
        pla
        ldx #0
        rts

; now = the time of the adapter (A = 1), else the program's or the first
; date (A = 0)
fill:   lda #<now
        ldx #>now
        jsr _plat_rtc
        cmp #0
        bne @rtc
        ldy #TIME_SIZE - 1
:       lda user,y
        sta now,y
        dey
        bpl :-
        lda #0
@rtc:   rts

; the time of the next entry into the FAT32 code's fat32_time_*: year -
; 1980 (0-127), month, day, hours, minutes, seconds
sd_time_fat:
        jsr fill
        lda now                         ; year - 1980, kept in 1980-2107
        sec
        sbc #<1980
        tax
        lda now+1
        sbc #>1980
        bcs :+
        ldx #0                          ; before 1980
        beq @y
:       bne @hi                         ; 2236 and later
        cpx #128
        bcc @y
@hi:    ldx #127
@y:     stx fat32_time_year
        ldy #4
:       lda now+2,y
        sta fat32_time_year+1,y
        dey
        bpl :-
        rts
