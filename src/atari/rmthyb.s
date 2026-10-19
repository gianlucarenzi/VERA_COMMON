; ============================================================================
; rmthyb.s - libvera, Atari: an RMT8 (stereo) song on POKEY + VERA PSG
; (rmt_init_hybrid, rmt_out_hybrid, rmt.h)
;
; The tracks of the left POKEY (1-4) play on the Atari's POKEY, the tracks
; of the right one (5-8) on VERA PSG voices 4-7 (psgrmt.s with psg_hybrid:
; voices 0-3 silent).  The player still runs from the VERA frame clock
; (rmtdrv.s); its left POKEY registers are in pokey_shadow, the right
; POKEY's channel state is read by psgrmt.s.  During SIO the POKEY plays
; only channels 1+2 (rmtpokey.s), the PSG half is not touched.
;
; Only in libvera_rmt8.lib (the player built for 8 tracks).
; ============================================================================

        .setcpu "6502"

        .export _rmt_init_hybrid, _rmt_out_hybrid
        .import rmt_init_core, _rmt_stop, out_update, out_silence
        .import pokey_update, pokey_silence
        .import psg_update, psg_silence, _psg_init, _psg_enable, _psg_hybrid

        .segment "CODE"

; unsigned char __fastcall__ rmt_init_hybrid(const void *module): the
; POKEY + PSG output, then the player on the module; returns the instrument
; speed
_rmt_init_hybrid:
        pha
        txa
        pha
        jsr _rmt_stop
        jsr _rmt_out_hybrid
        pla
        tax
        pla
        jmp rmt_init_core

; void rmt_out_hybrid(void): tracks 1-4 on POKEY, 5-8 on the VERA PSG
_rmt_out_hybrid:
        php
        sei
        jsr out_silence                 ; the chip that had the music
        jsr _psg_init
        lda #1
        sta _psg_hybrid                 ; PSG voices 0-3 silent
        sta _psg_enable
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

; VERA IRQ sound callback: the left POKEY, then the right one on the PSG
update:
        jsr pokey_update
        jmp psg_update

silence:
        jsr pokey_silence
        jmp psg_silence
