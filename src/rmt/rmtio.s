; ============================================================================
; rmtio.s - libvera: the "SIO transfer running" flag of the RMT player
;
; rmt_ioactive <> 0: POKEY channels 3+4 and AUDCTL are the serial clock, the
; player (rmtplayr.s SetPokey) and the POKEY output (rmtpokey.s) leave them
; alone.  In a module of its own so that a loader (sio.s) can set it without
; linking the player.  Set by rmt_io_begin / rmt_io_end (rmt.h).
; ============================================================================

        .export rmt_ioactive, _rmt_io_begin, _rmt_io_end

        .segment "DATA"

rmt_ioactive:   .byte 0

        .segment "CODE"

_rmt_io_begin:
        lda #1
        sta rmt_ioactive
        rts

_rmt_io_end:
        lda #0
        sta rmt_ioactive
        rts
