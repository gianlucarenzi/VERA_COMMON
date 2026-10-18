;-----------------------------------------------------------------------------
; nmos.inc - libvera: the 65C02 instructions of the FAT32 code on an NMOS
; 6502 (Atari, C64).  Each macro does what the instruction does: the same
; registers and flags changed, nothing else.  STZ, BRA and the stack ones
; are macros; (zp) without index, INC A / DEC A, TSB / TRB are rewritten
; where they are used.  The push / pull macros use two zero page bytes
; (nmos_t0 / nmos_t1): not reentrant, never called from an IRQ.
;-----------------------------------------------------------------------------

.globalzp nmos_t0, nmos_t1          ; fat32_vars.s

; STZ: no register, no flag changed
.macro stz arg1, arg2
	php
	pha
	lda #0
.ifblank arg2
	sta arg1
.else
	sta arg1,arg2
.endif
	pla
	plp
.endmacro

; BRA: always taken, no flag changed
.macro bra arg1
	jmp arg1
.endmacro

; PHX / PHY: push, A and flags kept
.macro phx
	sta nmos_t0
	php
	pla
	sta nmos_t1                     ; the flags
	txa
	pha
	lda nmos_t1
	pha
	lda nmos_t0
	plp
.endmacro

.macro phy
	sta nmos_t0
	php
	pla
	sta nmos_t1
	tya
	pha
	lda nmos_t1
	pha
	lda nmos_t0
	plp
.endmacro

; PLX / PLY: pull, N and Z from the value, A kept
.macro plx
	sta nmos_t0
	pla
	tax
	php
	lda nmos_t0
	plp
.endmacro

.macro ply
	sta nmos_t0
	pla
	tay
	php
	lda nmos_t0
	plp
.endmacro

; BIT #imm (65C02): Z = (A & imm) == 0; A, N, V, C kept.  No labels: a
; label in a macro would end the @local scope of the code around it.
.macro bitimm val
	sta nmos_t0
	php
	pla
	and #$FD                        ; the old flags without Z
	sta nmos_t1
	lda nmos_t0
	and #val                        ; the new Z
	php
	pla
	and #$02
	ora nmos_t1
	pha
	lda nmos_t0
	plp
.endmacro

; INC A / DEC A: N, Z from the result; C, V kept
.macro inca
	sta nmos_t0
	inc nmos_t0
	lda nmos_t0
.endmacro

.macro deca
	sta nmos_t0
	dec nmos_t0
	lda nmos_t0
.endmacro

; LDA / STA / CMP (zp): through (zp),y with Y = 0; Y kept, flags as the
; 65C02 instruction leaves them
.macro ldaind zp
	sty nmos_t0
	ldy #0
	lda (zp),y
	php
	ldy nmos_t0
	plp
.endmacro

.macro staind zp
	php
	sty nmos_t0
	ldy #0
	sta (zp),y
	ldy nmos_t0
	plp
.endmacro

.macro cmpind zp
	sty nmos_t0
	ldy #0
	cmp (zp),y
	php
	ldy nmos_t0
	plp
.endmacro
