; sim_sfx_stub.s - what sfx.s imports, for prof_sfx.c on sim65
        .export vera_irq_sfx, _vera_frame_init, _call_sfx
        .segment "BSS"
vera_irq_sfx:   .res 2
        .segment "CODE"
_vera_frame_init:
        rts
; void call_sfx(void): the effects callback as the VSYNC IRQ calls it
_call_sfx:
        lda #1
        jmp (vera_irq_sfx)
