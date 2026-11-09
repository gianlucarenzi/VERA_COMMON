;-----------------------------------------------------------------------------
; sdbank.inc - libvera, Atari: the RAMbo bank of the FAT32 code, for
; sdbank.s and sdbankw.s (the trampolines of the writing)
;-----------------------------------------------------------------------------

PORTB       = $D301
INITAD      = $02E2
SD_BANK     = %00000000                 ; bits 2, 3, 5, 6; bit 4 = 0: CPU
KEEP        = %10000011                 ; self test, BASIC, OS ROM bits
PATH_MAX    = 128                       ; as NAME_MAX of sdfs.s
DIRENT_SIZE = 256 + 1 + 4 + 4 + 6       ; struct sd_dirent

.macro  BANK_IN                         ; A lost
        lda PORTB
        sta SAVE
        and #KEEP
        ora #SD_BANK
        sta PORTB
.endmacro

.macro  BANK_OUT                        ; A, X kept
        ldy SAVE
        sty PORTB
.endmacro

; call A/X -> bk function with the bank in, A/X back
.macro  CALL fn
        sta TA
        stx TX
        BANK_IN
        lda TA
        ldx TX
        jsr fn
        BANK_OUT
        rts
.endmacro
