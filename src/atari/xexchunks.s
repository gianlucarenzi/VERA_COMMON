; ============================================================================
; xexchunks.s - libvera, Atari: the load chunks of the WIN and LOW memory
; areas of cfg/atari-rambo.cfg (WIN: GAMECODE, GAMERODATA in the main RAM at
; $4000-$7FFF; LOW: LOWRODATA below it, before XBSS which is not loaded).
; One pad byte in each keeps the chunk valid in a program that has none of
; those segments.
; ============================================================================

        .export         __XEX_CHUNKS__: absolute = 1
        .import         __WIN_START__, __WIN_LAST__
        .import         __LOW_START__, __LOWEND_LOAD__

        .segment "WINHDR"
        .word   __WIN_START__
        .word   __WIN_LAST__ - 1

        .segment "WINPAD"
        .byte   0

        .segment "LOWHDR"
        .word   __LOW_START__
        .word   __LOWEND_LOAD__ - 1

        .segment "LOWPAD"
        .byte   0

        .segment "LOWEND"               ; empty: where the chunk ends
