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
;   X16    the ROM pushes A, X, Y and jumps through CINV ($0314); the KERNAL
;          handler there takes every IRQ for the VERA VBLANK (keyboard,
;          joystick, clock) and acknowledges it
;
; IRQ_OURS_END: the end of an IRQ the hook served (pending = its sources).
; On the X16 a VSYNC goes on to the KERNAL too, or keyboard and joystick
; would stop; elsewhere it is IRQ_RETURN.

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

.elseif .defined(__CX16__)

IRQ_VECTOR              = $0314                     ; CINV

.macro  IRQ_ENTER
.endmacro

.macro  IRQ_CHAIN old
        jmp (old)                                   ; 65C02: no page-border bug
.endmacro

.macro  IRQ_RETURN
        pla                                         ; the ROM pushed A, X, Y
        tay
        pla
        tax
        pla
        rti
.endmacro

.macro  IRQ_OURS_END old, pending
        .local ret
        lda pending
        lsr a
        bcc ret
        jmp (old)                                   ; VSYNC: the KERNAL too
ret:    IRQ_RETURN
.endmacro

.else
.error "libvera: unsupported target (ca65 -t atari, -t c64 or -t cx16)"
.endif

.ifndef __CX16__
.macro  IRQ_OURS_END old, pending
        IRQ_RETURN
.endmacro
.endif
