; ============================================================================
; rmtpsg.s - libvera: the RMT music on the VERA PSG (psgrmt.s), the output
; of rmt_init and rmt_out_psg (rmt.h; the player core is rmtdrv.s)
; ============================================================================

        .setcpu "6502"

        .export _rmt_init, _rmt_out_psg
        .import rmt_init_core, _rmt_stop, out_update, out_silence
        .import psg_update, psg_silence, _psg_init, _psg_enable, _psg_hybrid

        .segment "CODE"

; unsigned char __fastcall__ rmt_init(const void *module): the PSG output,
; then the player on the module; returns the instrument speed (1..4)
_rmt_init:
        pha
        txa
        pha
        jsr _rmt_stop
        jsr _rmt_out_psg
        pla
        tax
        pla
        jmp rmt_init_core

; void rmt_out_psg(void): the music on the VERA PSG (the voices of the
; channel state the player computes, PAL / NTSC pitch of rmt_palnts)
_rmt_out_psg:
        php
        sei
        jsr out_silence                 ; the chip that had the music
        jsr _psg_init
        lda #<psg_update
        sta out_update+1
        lda #>psg_update
        sta out_update+2
        lda #<psg_silence
        sta out_silence+1
        lda #>psg_silence
        sta out_silence+2
        lda #0
        sta _psg_hybrid                 ; every channel on the PSG
        lda #1
        sta _psg_enable                 ; the voices follow the player
        plp
        rts
