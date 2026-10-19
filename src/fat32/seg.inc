;-----------------------------------------------------------------------------
; seg.inc - libvera: the segments of the FAT32 code.
;
; Normally CODE and BSS.  With -D FAT32_BANKED=1 (Atari, Makefile) BANKCODE
; and BANKBSS: cfg/atari-rambo.cfg loads them into a RAMbo bank at $4000, and
; src/atari/sdbank.s switches the bank in around every call (sdfs.s then
; exports its functions as bk_sd_*).
;-----------------------------------------------------------------------------

.macro FAT32_CODE
.ifdef FAT32_BANKED
        .segment "BANKCODE"
.else
        .segment "CODE"
.endif
.endmacro

.macro FAT32_BSS
.ifdef FAT32_BANKED
        .segment "BANKBSS"
.else
        .segment "BSS"
.endif
.endmacro
