; ============================================================================
; macptr.s - the X16 KERNAL block read (MACPTR) for asset.c
;
; MACPTR copies up to a whole 512-byte sector of the open file per call;
; CHRIN costs a trip through the DOS for every byte (the level stream lost
; frames with it).  The caller has done CHKIN on the file.
; ============================================================================

    .setcpu "65C02"

    .import popa
    .importzp tmp1
    .export _asset_macptr, _asset_macptr_fix

MACPTR          = $FF44                 ; A = bytes (0: to the end of the
                                        ; sector), Y:X = dst, C=1: dst fixed;
                                        ; out Y:X = bytes read, C=1 error

    .segment "CODE"

; ----------------------------------------------------------------------------
; unsigned __fastcall__ asset_macptr(unsigned char n, void *dst)
; unsigned __fastcall__ asset_macptr_fix(unsigned char n, void *dst)
;   n = 0: up to the end of the current sector (at most 512).  Returns the
;   bytes read, 0 = error.  _fix: every byte to the same address (VERA DATA0).
; ----------------------------------------------------------------------------
_asset_macptr:
    ldy #0
    bra common
_asset_macptr_fix:
    ldy #1
common:
    sty tmp1
    pha                                 ; dst
    phx
    jsr popa                            ; A = n
    ply
    plx
    lsr tmp1                            ; C = fixed dst
    jsr MACPTR
    bcs @err
    stx tmp1
    tya
    tax
    lda tmp1
    rts
@err:
    lda #0
    tax
    rts
