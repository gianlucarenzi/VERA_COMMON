; plat.inc - the host differences seen by the libvera assembly modules.
;
; Everything else in libvera is the same code on every host: the VERA is the
; same chip, only its base address (vera.inc) and the IRQ entry differ.
;
; IRQ entry contract, the same on every host once these macros are used:
;   a handler installed on IRQ_VECTOR starts with IRQ_ENTER; after it A, X
;   and Y are saved and may be changed.  It ends either with IRQ_CHAIN
;   old_vector (not ours: the previous handler runs with the registers as at
;   entry) or with IRQ_RETURN (ours: registers restored, RTI).
;
;   Atari  the OS reaches VIMIRQ ($0216) by JMP (VIMIRQ) with only P and PC
;          on the stack: IRQ_ENTER pushes A, X, Y itself
;   C64    the KERNAL ($FF48) pushes A, X, Y and jumps through CINV ($0314);
;          $EA81 pulls them and returns

.ifdef __ATARI__

IRQ_VECTOR              = $0216                     ; VIMIRQ

.macro  IRQ_ENTER
        pha
        txa
        pha
        tya
        pha
.endmacro

.macro  IRQ_CHAIN old
        pla
        tay
        pla
        tax
        pla
        jmp (old)
.endmacro

.macro  IRQ_RETURN
        pla
        tay
        pla
        tax
        pla
        rti
.endmacro

.elseif .defined(__C64__)

IRQ_VECTOR              = $0314                     ; CINV

.macro  IRQ_ENTER
.endmacro

.macro  IRQ_CHAIN old
        jmp (old)
.endmacro

.macro  IRQ_RETURN
        jmp $EA81                                   ; pla tay pla tax pla rti
.endmacro

.else
.error "libvera: unsupported target (ca65 -t atari or -t c64)"
.endif
