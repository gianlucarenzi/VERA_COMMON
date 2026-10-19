; sim_pcm_stub.s - what pcm.s imports, for prof_pcm.c on sim65 (no VERA,
; no IRQ: the VERA registers are plain RAM at $DE00, AUDIO_CTRL reads 0 =
; FIFO not full)

        .export vera_irq_pcm, _vera_frame_init, _call_tick, _tick_on

        .segment "BSS"
vera_irq_pcm:   .res 2

        .segment "CODE"
_vera_frame_init:
        rts

; unsigned char tick_on(void): 1 while the PCM callback is installed
_tick_on:
        lda vera_irq_pcm+1
        beq @r
        lda #1
@r:     ldx #0
        rts

; void call_tick(void): the PCM callback as the VSYNC IRQ calls it (A = VSYNC)
_call_tick:
        lda vera_irq_pcm+1
        beq @r
        lda #1
        jmp (vera_irq_pcm)
@r:     rts
