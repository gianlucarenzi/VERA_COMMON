; ============================================================================
; osram.s - libvera, Atari XL/XE: the OS ROM copied into the RAM under it
;
; unsigned char os_ram(void)
;   copies $C000-$CFFF and $D800-$FFFF (the OS and the floating point
;   package; $D000-$D7FF is I/O) into the RAM under the ROM and leaves the
;   ROM off (PORTB bit 0 = 0): the OS keeps running, from RAM, and its parts
;   become writable, e.g. the character set at $E000 (CHBAS $E0) can be
;   replaced in place, every text of E: and of the host screen then uses it.
;   1 = done (or already RAM), 0 = not an XL/XE (no RAM under the OS).
;
; The bank switches of libvera (sdbank.s, rmtdrv.s) keep PORTB bit 0
; (KEEP = %10000011), so the OS stays in RAM.  A RESET turns the ROM back
; on (PORTB = $FF): the RAM copy is then simply not seen.
; One byte at a time: ROM on to read, ROM off to write (a write with the ROM
; on does not reach the RAM); NMIs and IRQs off meanwhile (their vectors
; and handlers are in the area being switched).  ~0.4 s.
; The VERA card is deselected during the copy, so the Math Pack (not the
; card's ROM) is copied to $D800-$DFFF, then selected again.  With the card
; selected and the OS in RAM, a read of $D800-$DFFF finds both the card's
; ROM and the RAM on the bus: nothing may read there (no floating point).
; ============================================================================

        .export _os_ram
        .importzp ptr1

PORTB   = $D301
NMIEN   = $D40E
PBI_LATCH = $D1FF
SHPDVS  = $0248                         ; OS shadow of $D1FF

; GAMECODE: in cfg/atari-rambo.cfg the window $4000-$7FFF in the main RAM
; (PORTB bit 0 only changes here, no bank), MAIN is the full one
        .segment "GAMECODE"

_os_ram:
        lda PORTB
        lsr a                           ; bit 0 = 0: already RAM
        bcc @yes
        ; an XL/XE? the RAM under $C000 must answer (a 400/800 has none)
        php
        sei
        lda #0
        sta NMIEN
        sta PBI_LATCH                   ; card off: the Math Pack is read
        lda #$C0
        sta ptr1+1
        lda #0
        sta ptr1
@page:  ldy #0
@byte:  lda (ptr1),y                    ; ROM on
        tax
        lda PORTB
        and #$FE
        sta PORTB                       ; ROM off: the RAM under it
        txa
        sta (ptr1),y
        lda PORTB
        ora #$01
        sta PORTB                       ; ROM on
        iny
        bne @byte
        inc ptr1+1
        lda ptr1+1
        cmp #$D0                        ; skip the I/O area
        bne :+
        lda #$D8
        sta ptr1+1
:       lda ptr1+1
        bne @page                       ; up to $FFFF
        ; check one byte, then the ROM off for good
        lda PORTB
        and #$FE
        sta PORTB
        lda $E000
        eor #$FF
        sta $E000
        cmp $E000
        php
        eor #$FF
        sta $E000
        plp
        beq @ram                        ; writable: RAM there, the ROM stays off
        lda PORTB                       ; not writable: no RAM there, ROM on
        ora #$01
        sta PORTB
        ldy #0                          ; result 0
        .byte $2C                       ; BIT abs: skips the LDY #1
@ram:   ldy #1                          ; result 1
        lda SHPDVS                      ; the card selected again
        sta PBI_LATCH
        lda #$40                        ; the VBI again (the OS default)
        sta NMIEN
        plp
        tya
        .byte $2C                       ; BIT abs: skips the LDA #1
@yes:   lda #1
        ldx #0
        rts
