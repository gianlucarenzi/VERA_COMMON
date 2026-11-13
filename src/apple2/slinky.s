; ============================================================================
; slinky.s - libvera, Apple II: a Slinky RAM card (Apple II Memory Expansion
; Card compatible), e.g. the 256 KB of the VERA Module RBL-A2 (C interface:
; slinky.h)
;
; Registers of the card in slot n ($C080 + n * 16):
;   $C0n0 / $C0n1 / $C0n2  address bits 0-7 / 8-15 / 16-23 (read: $C0n2 has
;                          $F0 ORed in, as on Apple's card)
;   $C0n3                  the byte at the address, then address + 1
; Every access is LDA / STA (zp,X) with X = 0: on an NMOS 6502 an indexed
; store (STA abs,X / STA (zp),Y) first makes a dummy read of the target,
; which on $C0n3 would advance the address (the RBL-A2 ROM does the same).
; ptr1 = the register of the moment, ptr2 = the main RAM buffer.
; ============================================================================

        .setcpu "6502"
        .macpack longbranch

        .export _slinky_find, _slinky_open, _slinky_seek, _slinky_read, _slinky_write
        .import popax
        .importzp ptr1, ptr2, sreg, tmp1, tmp2, tmp3

ID_OFS      = $F0                       ; "VERAS" at $CnF0: VERA Module RBL-A2

        .bss
reg0:   .res 1                          ; low byte of $C0n0 (0 = no card open)
cnt:    .res 2
b0:     .res 1                          ; slinky_open: the bytes it touches
bk:     .res 1
k:      .res 1

        .rodata
rbl_sig: .byte $56, $45, $52, $41, $53  ; "VERAS" in ASCII (no charmap)

        .code

; ----------------------------------------------------------------------------
; unsigned char slinky_find(void): the slot of an RBL-A2, 0 = none (reads only)
; ----------------------------------------------------------------------------
_slinky_find:
        lda #ID_OFS
        sta ptr1
        lda #$C7                        ; slot 7 down to 1
        sta ptr1+1
@slot:  ldy #4
@id:    lda (ptr1),y
        cmp rbl_sig,y
        bne @next
        dey
        bpl @id
        lda ptr1+1
        and #7
        ldx #0
        rts
@next:  dec ptr1+1
        lda ptr1+1
        cmp #$C1
        bcs @slot
        lda #0
        tax
        rts

; ----------------------------------------------------------------------------
; set ptr1 to register A ($C0n0 + A) of the open card; X = 0
; ----------------------------------------------------------------------------
regp:   clc
        adc reg0
        sta ptr1
        lda #$C0
        sta ptr1+1
        ldx #0
        rts

; the 24-bit address tmp1 (0-7) / tmp2 (8-15) / tmp3 (16-23) into the card;
; leaves ptr1 at $C0n3, X = 0
setadr: lda #0
        jsr regp
        lda tmp1
        sta (ptr1,x)
        inc ptr1
        lda tmp2
        sta (ptr1,x)
        inc ptr1
        lda tmp3
        sta (ptr1,x)
        inc ptr1
        rts

; ----------------------------------------------------------------------------
; unsigned char __fastcall__ slinky_open(unsigned char slot): the size in
; 64 KB units (16 = 1 MB or more), 0 = no card
; ----------------------------------------------------------------------------
_slinky_open:
        and #7
        jeq @none
        asl a
        asl a
        asl a
        asl a
        ora #$80
        sta reg0
        ; the address registers keep what is written ($C0n2: its low 4 bits)
        lda #$A5
        sta tmp1
        lda #$5A
        sta tmp2
        lda #$03
        sta tmp3
        jsr setadr
        lda #0
        jsr regp
        lda (ptr1,x)
        cmp #$A5
        jne @none
        inc ptr1
        lda (ptr1,x)
        cmp #$5A
        jne @none
        inc ptr1
        lda (ptr1,x)
        ora #$F0                        ; (the bits above the card's: $F on Apple's
        cmp #$F3                        ; card and the RBL-A2, not on every clone)
        jne @none
        ; size: the first k (1, 2, 4, 8) whose k * 64 KB is the byte at 0
        lda #0
        sta tmp3
        jsr setadr0
        lda (ptr1,x)
        sta b0
        lda #1
        sta k
@size:  jsr setadrk
        lda (ptr1,x)
        sta bk                          ; the byte at k * 64 KB
        jsr setadrk
        lda b0
        eor #$FF
        sta (ptr1,x)                    ; ~b0 there
        lda #0
        sta tmp3
        jsr setadr0
        lda (ptr1,x)                    ; does 0 show it?
        eor #$FF
        cmp b0
        bne @back
        jsr setadr0                     ; a mirror: b0 back (the same cell)
        lda b0
        sta (ptr1,x)
        lda k
        rts                             ; (X = 0)
@back:  jsr setadrk                     ; not a mirror: bk back, next k
        lda bk
        sta (ptr1,x)
        asl k
        lda k
        cmp #16
        bcc @size
        ldx #0
        rts                             ; 16: 1 MB or more (A = 16)
@none:  lda #0
        sta reg0
        tax
        rts

setadrk:
        lda k
        sta tmp3
setadr0:
        lda #0
        sta tmp1
        sta tmp2
        jmp setadr

; ----------------------------------------------------------------------------
; void __fastcall__ slinky_seek(unsigned long addr)
; ----------------------------------------------------------------------------
_slinky_seek:
        sta tmp1
        stx tmp2
        lda sreg
        sta tmp3
        jmp setadr

; ----------------------------------------------------------------------------
; void __fastcall__ slinky_read(void *dst, unsigned n)
; void __fastcall__ slinky_write(const void *src, unsigned n)
; ----------------------------------------------------------------------------
_slinky_read:
        jsr args
        beq @tail
@page:  lda (ptr1,x)                    ; whole pages
        sta (ptr2),y
        iny
        bne @page
        inc ptr2+1
        dec cnt+1
        bne @page
@tail:  ldy cnt
        beq @done
        ldy #0
@last:  lda (ptr1,x)
        sta (ptr2),y
        iny
        cpy cnt
        bne @last
@done:  rts

_slinky_write:
        jsr args
        beq @tail
@page:  lda (ptr2),y
        sta (ptr1,x)
        iny
        bne @page
        inc ptr2+1
        dec cnt+1
        bne @page
@tail:  ldy cnt
        beq @done
        ldy #0
@last:  lda (ptr2),y
        sta (ptr1,x)
        iny
        cpy cnt
        bne @last
@done:  rts

; n (A/X) -> cnt, the buffer (C stack) -> ptr2, ptr1 = $C0n3, X = Y = 0,
; Z = 1 when there is no whole page
args:   sta cnt
        stx cnt+1
        jsr popax
        sta ptr2
        stx ptr2+1
        lda #3
        jsr regp
        ldy #0
        lda cnt+1
        rts
