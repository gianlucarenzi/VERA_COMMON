; ============================================================================
; basicoff.s - libvera, Atari XL/XE: switch the BASIC ROM off before the
; program loads, so $A000-$BFFF is RAM for it (cfg/atari.cfg uses it).
;
; An XL/XE boots with BASIC on unless OPTION is held: the program must not
; rely on that (nor on an emulator without the BASIC ROM).  This is a load
; chunk of its own, the first one of the executable after the header: DOS
; loads it and runs it (INITAD) before the system check of cc65 and before
; the main chunk, which loads into $A000-$BC1F too.
;
; BASIC on (PORTB bit 1 = 0): PORTB bit 1 = 1 (ROM off), BASICF = 1 (stays
; off after RESET), RAMTOP = $C0, then E: is closed and opened again, so the
; OS moves the screen to the top of the RAM and sets MEMTOP.
; BASIC already off: nothing.  The chunk is overwritten later by the
; program (it loads at $2E00 as the system check does).
; It also switches the key click off (NOCLIK = 1): the OS click of every key
; press on the console speaker would sound over the game.
; ============================================================================

        .export         __BASIC_OFF__: absolute = 1
        .import         __BASOFF_LOAD__, __BASOFF_SIZE__

PORTB   = $D301
RAMTOP  = $6A
BASICF  = $03F8                 ; 0 = BASIC on after RESET
NOCLIK  = $02DB                 ; <> 0 = no key click (XL OS)
INITAD  = $02E2
CIOV    = $E456
ICCOM   = $0342                 ; IOCB 0
ICBAL   = $0344
ICBAH   = $0345
ICAX1   = $034A
ICAX2   = $034B
OPEN    = 3
CLOSE   = 12

        .segment "BASOFFHDR"
        .word   __BASOFF_LOAD__
        .word   __BASOFF_LOAD__ + __BASOFF_SIZE__ - 1

        .segment "BASOFF"
basic_off:
        lda     #1
        sta     NOCLIK          ; no key click
        lda     PORTB
        and     #$02
        bne     done            ; BASIC already off
        lda     PORTB
        ora     #$02
        sta     PORTB           ; BASIC ROM off: $A000-$BFFF is RAM
        lda     #1
        sta     BASICF          ; and it stays off after RESET
        lda     #$C0
        sta     RAMTOP          ; the RAM ends at $BFFF
        ldx     #0              ; reopen E: (IOCB 0): screen at the top,
        lda     #CLOSE          ; MEMTOP below it
        sta     ICCOM
        jsr     CIOV
        ldx     #0
        lda     #OPEN
        sta     ICCOM
        lda     #<edev
        sta     ICBAL
        lda     #>edev
        sta     ICBAH
        lda     #$0C            ; read + write
        sta     ICAX1
        lda     #0
        sta     ICAX2
        jsr     CIOV
done:   rts
edev:   .byte   "E:", $9B

        .segment "BASOFFTRL"
        .word   INITAD
        .word   INITAD+1
        .word   basic_off
