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
;
; High speed SIO: the first call asks the drive for its speed, as the
; high speed OS patches do (short timeout: a stock 1050 just NAKs):
;   $3F  "get speed index" (US Doubler, SDrive, SIO2SD, FujiNet, SIO2PC):
;        the POKEY divisor of the drive (>= MIN_DIV, else not used); then
;        command frames and responses at that speed
;   $D3  XF551 status: commands with bit 7 set, sent at 19200, the drive
;        answers at 38400 (divisor $10); atari800 emulates only this one
;   else the standard 19200.  A failed transfer at high speed falls back
;   to the standard speed for good and is retried once.
; sio_div (exported) is the divisor of the responses: $28 standard.
; ============================================================================

        .setcpu "6502"

        .export _sio_read_sector, _sio_div
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
XF551_DIV  = $10                ; 38400 baud
MIN_DIV    = 6                  ; faster: bytes closer than the IRQ latency
TIMEOUT    = 150                ; frames (3 s PAL)
TMO_PROBE  = 10                 ; frames, the speed questions

; speed modes
M_PROBE  = 0                    ; not asked yet
M_STD    = 1
M_XF551  = 2
M_US     = 3                    ; $3F: everything at sio_div

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

        .segment "DATA"
mode:   .byte M_PROBE
_sio_div: .byte BAUD_AUDF3

        .segment "BSS"
cmdframe: .res 5
len:    .res 1                  ; data bytes of the response
cmddiv: .res 1                  ; divisor of the command frame
tmo:    .res 1
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

        lda mode
        bne @read
        ; --- the speed questions, once (the answers in the sector buffer) ---
        lda #TMO_PROBE
        sta tmo
        lda #1                  ; $3F: one byte, the divisor
        sta len
        lda #$3F
        jsr std_cmd
        bne @xf
        tay                     ; A = 1
        dey
        lda (bufp),y
        cmp #MIN_DIV
        bcc @xf
        sta _sio_div
        lda #M_US
        bne @setm
@xf:    lda #4                  ; XF551 status at 38400: 4 bytes
        sta len
        lda #XF551_DIV
        sta _sio_div
        lda #$D3
        jsr std_cmd2
        beq @isxf
        lda #BAUD_AUDF3
        sta _sio_div
        lda #M_STD
        .byte $2C               ; skip the next lda
@isxf:  lda #M_XF551
@setm:  sta mode

@read:  lda #TIMEOUT
        sta tmo
        lda #128
        sta len
        lda #'R'
        ldx mode
        cpx #M_XF551
        bne :+
        ora #$80
:       ldy #BAUD_AUDF3         ; the command frame: 19200
        cpx #M_US
        bne :+
        ldy _sio_div            ; ... or the drive's speed
:       jsr xfer
        cmp #1
        beq @ret
        ldx mode                ; failed at high speed: the standard one
        dex                     ; M_STD
        beq @ret
        lda #M_STD
        sta mode
        lda #BAUD_AUDF3
        sta _sio_div
        bne @read               ; always
@ret:   ldx #0
        rts

; command A at 19200 with the response at 19200 (std_cmd) or at sio_div
; (std_cmd2); Z = 1 on success
std_cmd:
        ldy #BAUD_AUDF3
        sty _sio_div
std_cmd2:
        ldy #BAUD_AUDF3
        jsr xfer
        cmp #1
        rts

; one transfer: A = command, Y = divisor of the command frame, the
; response at sio_div into bufp (len bytes); A = the status
xfer:
        sta cmdframe+1
        sty cmddiv
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
        lda cmddiv
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
        lda _sio_div            ; the speed of the response
        sta AUDF3
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
        cmp tmo
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
        cpy len
        bne @out                ; not all yet
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
