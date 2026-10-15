; ============================================================================
; vmem.s - VRAM transfer primitives (C interface: vmem.h)
;
; Every libvera module and the game move VRAM data through these, so they
; are the place for speed: the copy loops are unrolled 4 times (about 11
; cycles a byte instead of 14), the fill 8 times (about 5), and the 32 bit
; fill uses the FX write cache (4 bytes per DATA0 write, about 1.3 cycles a
; byte).
;
; They all work on data port 0 at the address and increment set by
; vram_seek (DATA1 is the source of vram_copy).  CTRL is left at 0.
; ============================================================================

    .setcpu "6502"
    .include "vera.inc"
    .include "zeropage.inc"

    .export _vram_seek, _vram_seek1
    .export _vram_write, _vram_read, _vram_fill, _vram_fill32, _vram_copy
    .import popa, popptr1
    .importzp sreg

    .segment "BSS"

cnt:    .res 2

    .segment "CODE"

; ----------------------------------------------------------------------------
; void __fastcall__ vram_seek(unsigned long vaddr)
;   A = bits 7:0, X = bits 15:8, sreg = ADDR_H (bank | increment, VRAM())
; ----------------------------------------------------------------------------
_vram_seek:
    ldy #0
    sty VERA_CTRL
    sta VERA_ADDR_L
    stx VERA_ADDR_M
    lda sreg
    sta VERA_ADDR_H
    rts

; void __fastcall__ vram_seek1(unsigned long vaddr) - the same for port 1
_vram_seek1:
    ldy #1
    sty VERA_CTRL               ; ADDRSEL = 1
    sta VERA_ADDR_L
    stx VERA_ADDR_M
    lda sreg
    sta VERA_ADDR_H
    dey
    sty VERA_CTRL
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vram_write(const void *src, unsigned n)   RAM -> DATA0
; ----------------------------------------------------------------------------
_vram_write:
    sta cnt
    stx cnt+1
    jsr popptr1                 ; ptr1 = src, Y = 0
    ldx cnt+1
    beq @tail
@page:                          ; whole pages, 4 bytes per round
    lda (ptr1),y
    sta VERA_DATA0
    iny
    lda (ptr1),y
    sta VERA_DATA0
    iny
    lda (ptr1),y
    sta VERA_DATA0
    iny
    lda (ptr1),y
    sta VERA_DATA0
    iny
    bne @page
    inc ptr1+1
    dex
    bne @page
@tail:
    ldx cnt
    beq @done
@byte:
    lda (ptr1),y
    sta VERA_DATA0
    iny
    dex
    bne @byte
@done:
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vram_read(void *dst, unsigned n)    DATA0 -> RAM
; ----------------------------------------------------------------------------
_vram_read:
    sta cnt
    stx cnt+1
    jsr popptr1
    ldx cnt+1
    beq @tail
@page:
    lda VERA_DATA0
    sta (ptr1),y
    iny
    lda VERA_DATA0
    sta (ptr1),y
    iny
    lda VERA_DATA0
    sta (ptr1),y
    iny
    lda VERA_DATA0
    sta (ptr1),y
    iny
    bne @page
    inc ptr1+1
    dex
    bne @page
@tail:
    ldx cnt
    beq @done
@byte:
    lda VERA_DATA0
    sta (ptr1),y
    iny
    dex
    bne @byte
@done:
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vram_fill(unsigned char value, unsigned n)
; ----------------------------------------------------------------------------
_vram_fill:
    sta cnt
    stx cnt+1
    jsr popa                    ; A = value
    ldy cnt+1
    beq @tail
    ldx #32                     ; 32 x 8 = 256 bytes
@page:
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    dex
    bne @page
    ldx #32
    dey
    bne @page
@tail:
    ldx cnt
    beq @done
@byte:
    sta VERA_DATA0
    dex
    bne @byte
@done:
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vram_fill32(unsigned char value, unsigned nquads)
;   4 * nquads bytes of value through the FX 32 bit cache.  Port 0 must be
;   at a 4 byte aligned address with increment 4 (VRAM(a, VERA_INC4)).
; ----------------------------------------------------------------------------
_vram_fill32:
    sta cnt
    stx cnt+1
    jsr popa
    ldx #VERA_DCSEL6
    stx VERA_CTRL
    sta VERA_FX_CACHE_L         ; the 4 cache bytes
    sta VERA_FX_CACHE_M
    sta VERA_FX_CACHE_H
    sta VERA_FX_CACHE_U
    ldx #VERA_DCSEL2
    stx VERA_CTRL
    lda #VERA_FX_CACHE_WR_EN
    sta VERA_FX_CTRL
    lda #0                      ; byte mask: all 4 bytes written
    ldy cnt+1
    beq @tail
    ldx #32
@page:
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    sta VERA_DATA0
    dex
    bne @page
    ldx #32
    dey
    bne @page
@tail:
    ldx cnt
    beq @done
@quad:
    sta VERA_DATA0
    dex
    bne @quad
@done:
    sta VERA_FX_CTRL            ; A = 0: FX off (CTRL is still DCSEL 2)
    sta VERA_CTRL
    rts

; ----------------------------------------------------------------------------
; void __fastcall__ vram_copy(unsigned n)    DATA1 -> DATA0 (VRAM to VRAM)
;   Port 1 is the source (vram_seek1), port 0 the destination (vram_seek).
; ----------------------------------------------------------------------------
_vram_copy:
    sta cnt
    txa
    tay
    beq @tail
    ldx #0
@page:
    lda VERA_DATA1
    sta VERA_DATA0
    lda VERA_DATA1
    sta VERA_DATA0
    lda VERA_DATA1
    sta VERA_DATA0
    lda VERA_DATA1
    sta VERA_DATA0
    inx
    cpx #64                     ; 64 x 4 = 256 bytes
    bne @page
    ldx #0
    dey
    bne @page
@tail:
    ldx cnt
    beq @done
@byte:
    lda VERA_DATA1
    sta VERA_DATA0
    dex
    bne @byte
@done:
    rts
