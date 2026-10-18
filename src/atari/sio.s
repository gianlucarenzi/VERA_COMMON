; ============================================================================
; sio.s - libvera, Atari: sector read through an own IRQ driven SIO driver
; (AT2019 PokeyATest, rbl_read_sector), safe with music in an interrupt.
;
; The OS SIOV is not: after the drive "Complete" byte the OS re-arms the
; receiver from main code, and a long interrupt there (the music player)
; loses the first data byte: the sector comes in shifted by one byte, and
; the OS may even return status 1.  Here the whole response (ACK,
; Complete, 128 data bytes, checksum) is received by a state machine in the
; VSERIN IRQ handler: no main code in the critical path.  The command frame
; is sent polled with IRQs masked (the VERA IRQ, and so the music, waits a
; few milliseconds).  POKEY channels 3/4 are programmed silent.
;
; The caller brackets its transfers with rmt_io_begin / rmt_io_end (rmt.h)
; so that the music keeps off channels 3/4 and AUDCTL (asset_dsk.c does).
;
; unsigned char __fastcall__ sio_read_sector(unsigned char unit,
;                                            unsigned sector, void* buf);
; return: 1 = OK, 138 timeout, 139 NAK, 140 serial framing/overrun,
;         143 checksum, 144 device error. 128 bytes sectors only (SD/ED).
; ============================================================================

        .setcpu "6502"

        .export _sio_read_sector
        .import popa, popax


RTCLOK  = $12
POKMSK  = $10
VSERIN  = $020A
SSKCTL  = $0232

AUDF3   = $D204
AUDC3   = $D205
AUDF4   = $D206
AUDC4   = $D207
AUDCTL  = $D208
SKRES   = $D20A
SEROUT  = $D20D
SERIN   = $D20D
IRQEN   = $D20E
IRQST   = $D20E
SKCTL   = $D20F
SKSTAT  = $D20F
PBCTL   = $D303

BAUD_AUDF3 = $28                ; 19200 baud (OS standard)
TIMEOUT    = 150                ; frames (3 s PAL)

; state machine
ST_ACK   = 0
ST_CPL   = 1
ST_DATA  = 2
ST_CHK   = 3
ST_OK    = 4                    ; >= ST_OK: finished
ST_NAK   = 5
ST_DERR  = 6
ST_CKERR = 7
ST_SERR  = 8

        .segment "ZEROPAGE"
bufp:   .res 2

        .segment "BSS"
cmdframe: .res 5
state:  .res 1
cnt:    .res 1
chk:    .res 1
t0:     .res 1
oldserin: .res 2

        .segment "RODATA"
; DSTATS style result for every final state (ST_OK..ST_SERR)
resulttab: .byte 1, 139, 144, 143, 140

        .segment "CODE"

; ---------------------------------------------------------------------------
_sio_read_sector:
        sta bufp
        stx bufp+1
        jsr popax               ; sector number
        sta cmdframe+2
        stx cmdframe+3
        jsr popa                ; drive unit 1..8
        clc
        adc #$30                ; $31 = D1:
        sta cmdframe
        lda #'R'
        sta cmdframe+1
        ; command frame checksum (8 bit add with end around carry)
        lda #0
        ldx #3
@ck:    clc
        adc cmdframe,x
        adc #0
        dex
        bpl @ck
        sta cmdframe+4

        sei
        ; POKEY ch3+4 = 16 bit baud rate generator, silent
        lda #$28
        sta AUDCTL
        lda #BAUD_AUDF3
        sta AUDF3
        lda #0
        sta AUDF4
        lda #$A0
        sta AUDC3
        sta AUDC4

        lda VSERIN
        sta oldserin
        lda VSERIN+1
        sta oldserin+1
        lda #<serin_irq
        sta VSERIN
        lda #>serin_irq
        sta VSERIN+1

        ; --- command frame, polled, IRQs masked ---
        lda SSKCTL
        and #$07
        ora #$20                ; async transmit, clock from ch4
        sta SKCTL
        sta SKRES
        lda #$34                ; command line asserted
        sta PBCTL
        lda POKMSK
        and #$C7
        sta IRQEN               ; no serial IRQ pending
        lda cmdframe            ; first byte straight in (as the OS does):
        sta SEROUT              ; "output needed" fires once it is moved
        ldx #1                  ; into the shift register
@tx:    lda POKMSK
        and #$C7
        ora #$10                ; serial output needed
        sta IRQEN
@w1:    lda IRQST
        and #$10
        bne @w1
        lda cmdframe,x
        sta SEROUT
        lda POKMSK
        and #$C7
        sta IRQEN               ; acknowledge
        inx
        cpx #5
        bne @tx
        lda POKMSK
        and #$C7
        ora #$08                ; transmission done
        sta IRQEN
@w2:    lda IRQST
        and #$08
        bne @w2
        lda POKMSK
        and #$C7
        sta IRQEN

        ; --- response, IRQ driven ---
        lda #0
        sta state
        sta cnt
        sta chk
        lda SSKCTL
        and #$07
        ora #$10                ; async receive
        sta SKCTL
        sta SKRES
        lda #$3C                ; command line released
        sta PBCTL
        lda POKMSK              ; the OS IRQ handler re-enables IRQEN from
        ora #$20                ; POKMSK, so the SERIN bit goes in both
        sta POKMSK
        sta IRQEN
        lda RTCLOK+2
        sta t0
        cli

@wait:  lda state
        cmp #ST_OK
        bcs @done
        lda RTCLOK+2
        sec
        sbc t0
        cmp #TIMEOUT
        bcc @wait
        lda #138                ; timeout
        bne @fin
@done:  sec
        sbc #ST_OK
        tax
        lda resulttab,x
@fin:   tax
        sei
        lda POKMSK
        and #$DF
        sta POKMSK
        sta IRQEN
        lda oldserin
        sta VSERIN
        lda oldserin+1
        sta VSERIN+1
        cli
        txa
        ldx #0
        rts

; ---------------------------------------------------------------------------
; VSERIN handler. The OS has pushed A and already acknowledged the IRQ.
serin_irq:
        tya
        pha
        lda SKSTAT
        sta SKRES               ; reset serial error latches
        and #$A0                ; bit7=0 framing error, bit5=0 overrun
        cmp #$A0
        bne @serr
        lda SERIN
        ldy state
        beq @ack
        dey
        beq @cpl
        dey
        beq @data
        dey
        beq @chk
        bne @out                ; finished: ignore further bytes

@ack:   cmp #'A'
        bne @nak
        inc state
        bne @out
@nak:   lda #ST_NAK
        bne @set

@cpl:   cmp #'C'
        bne @derr
        inc state
        bne @out
@derr:  lda #ST_DERR
        bne @set

@data:  ldy cnt
        sta (bufp),y
        clc
        adc chk
        adc #0
        sta chk
        iny
        sty cnt
        bpl @out                ; < 128 bytes
        inc state               ; -> ST_CHK
        bne @out

@chk:   cmp chk
        bne @ckerr
        lda #ST_OK
        bne @set
@ckerr: lda #ST_CKERR
        bne @set

@serr:  lda SERIN
        lda state
        cmp #ST_OK
        bcs @out
        lda #ST_SERR
@set:   sta state
@out:
        pla
        tay
        pla
        rti
