; ============================================================================
; rmtrmt.s - libvera: the RMT routine (rmtplayr.s or lzsplayr.s) as the
; player of rmtdrv.s.  rmt_init_core is called by the rmt_init* of the
; output modules (rmtpsg.s, rmtpokey.s, rmtsid.s) once they set the output.
; ============================================================================

        .setcpu "6502"

        .export rmt_init_core
        .import RASTERMUSICTRACKER
        .import _rmt_stop, _rmt_ispeed, player_play, player_silence

rmt_init    = RASTERMUSICTRACKER+0      ; X/Y = module, A = song line
rmt_play    = RASTERMUSICTRACKER+3
rmt_silence = RASTERMUSICTRACKER+9

        .segment "CODE"

; rmt_init_core: A/X = module.  Music stopped first.  Returns A = instrument
; speed (1..4), X = 0.
rmt_init_core:
        pha
        txa
        pha
        jsr _rmt_stop
        lda #<rmt_play                  ; the RMT routine plays
        sta player_play+1
        lda #>rmt_play
        sta player_play+2
        lda #<rmt_silence
        sta player_silence+1
        lda #>rmt_silence
        sta player_silence+2
        pla                             ; X = lo, Y = hi for the player
        tay
        pla
        tax
        lda #0                          ; from song line 0
        jsr rmt_init                    ; A = instrument speed
        cmp #1                          ; clamp to 1..4 (RMT format range)
        bcs @lo
        lda #1
@lo:    cmp #5
        bcc @hi
        lda #4
@hi:    sta _rmt_ispeed
        ldx #0
        rts
