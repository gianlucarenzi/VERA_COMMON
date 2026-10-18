; ============================================================================
; rmtpokey.s - libvera, Atari: the RMT music on POKEY (rmt_out_host, rmt.h)
;
; The player (rmtplayr.s, RMT_SHADOW) still runs from the VERA frame clock
; (rmtdrv.s) and writes its POKEY registers to pokey_shadow; this module
; takes the output of rmtdrv.s and copies them to the POKEY once per frame.
;
; SIO: while a transfer runs POKEY channels 3+4 and AUDCTL are the serial
; baud rate generator.  During rmt_io_begin .. rmt_io_end (own SIO driver,
; sio.s, rmtio.s) or with CRITIC <> 0 (the OS SIO) only channels 1+2 are written,
; channels 3+4 are held at volume 0 (the volume does not disturb the
; timers): the music goes on with channels 1+2, the loading is silent.
; The player sees rmt_ioactive too and keeps the shadow of 3/4 silent.
; (From AT2019 PokeyATest, rmtvbi.s.)
; ============================================================================

        .setcpu "6502"

        .export _rmt_init_host, _rmt_out_host
        .import rmt_init_core, _rmt_stop, out_update, out_silence
        .import pokey_shadow, rmt_ioactive

POKEY   = $D200
AUDCTL  = POKEY + 8
CRITIC  = $42

        .segment "CODE"

; unsigned char __fastcall__ rmt_init_host(const void *module): the host
; output, then the player on the module; returns the instrument speed
_rmt_init_host:
        pha
        txa
        pha
        jsr _rmt_stop
        jsr _rmt_out_host
        pla
        tax
        pla
        jmp rmt_init_core

; void rmt_out_host(void): the music on POKEY instead of the VERA PSG
_rmt_out_host:
        php
        sei
        jsr out_silence                 ; the chip that had the music
        lda #<update
        sta out_update+1
        lda #>update
        sta out_update+2
        lda #<silence
        sta out_silence+1
        lda #>silence
        sta out_silence+2
        plp
        rts

; the shadow registers -> POKEY (VERA IRQ sound callback, I = 0)
update:
        ldx #3                          ; AUDF1 AUDC1 AUDF2 AUDC2
@12:    lda pokey_shadow,x
        sta POKEY,x
        dex
        bpl @12
        lda rmt_ioactive
        ora CRITIC
        bne io
        ldx #8                          ; AUDF3 AUDC3 AUDF4 AUDC4 AUDCTL
@34:    lda pokey_shadow,x
        sta POKEY,x
        dex
        cpx #4
        bcs @34
        rts
io:     lda #0                          ; SIO owns channels 3/4 and AUDCTL
        sta POKEY+5
        sta POKEY+7
        rts

; all channels at volume 0
silence:
        lda #0
        sta POKEY+1
        sta POKEY+3
        sta POKEY+5
        sta POKEY+7
        rts
