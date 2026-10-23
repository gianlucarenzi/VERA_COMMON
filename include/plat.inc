; plat.inc - the host differences seen by the libvera assembly modules.
;
; Everything else in libvera is the same code on every host: the VERA is the
; same chip, only its base address (vera.inc) and the IRQ entry differ.
;
; IRQ entry contract, the same on every host once these macros are used:
;   a handler installed on IRQ_VECTOR starts with IRQ_ENTER; after it A, X
;   and Y are saved and may be changed.  It ends either with IRQ_CHAIN
;   old_jmp (not ours: the previous handler runs with the registers as at
;   entry; old_jmp is a JMP abs instruction in RAM whose operand is the old
;   vector, never a "jmp (abs)": on the NMOS 6502 that breaks when the
;   vector lands on $xxFF) or with IRQ_RETURN (ours: registers restored, RTI).
;
;   Atari  the OS reaches VIMIRQ ($0216) by JMP (VIMIRQ) with only P and PC
;          on the stack: IRQ_ENTER pushes A, X, Y itself.  The VERA answers
;          only while its PBI bit is set in $D1FF (Atari PBI rule): IRQ_ENTER
;          selects the card, because the OS may have deselected it (SIO of
;          another PBI device), and IRQ_CHAIN / IRQ_RETURN put back the
;          selection the OS knows of (SHPDVS, plat_atari.s keeps it = the
;          card).  An IRQ that read the VERA deselected would see ISR & IEN
;          = $FF and never clear the level IRQ of the VERA
;   C64    the KERNAL ($FF48) pushes A, X, Y and jumps through CINV ($0314);
;          $EA81 pulls them and returns
;   X16    the ROM pushes A, X, Y and jumps through CINV ($0314); the KERNAL
;          handler there takes every IRQ for the VERA VBLANK (keyboard,
;          joystick, clock) and acknowledges it
;   Apple  the Monitor ROM's IRQ code saves A in $45 and jumps through
;          $03FE with only P and PC on the stack; with the language card RAM
;          in (cc65 programs), the 6502 vector $FFFE is RAM: IRQ_HOST_INSTALL
;          points it at plat_apple2.s's entry, which does the same as the
;          ROM (the ROM stays out), so both ways reach $03FE alike.
;          IRQ_ENTER pushes A (from $45), X, Y itself
;
; IRQ_HOST_INSTALL: in vera_irq_install, IRQs off, before IRQ_VECTOR is
; taken (Apple: the language card vector; nothing elsewhere).
;
; IRQ_OURS_END: the end of an IRQ the hook served (pending = its sources).
; On the X16 a VSYNC goes on to the KERNAL too, or keyboard and joystick
; would stop; elsewhere it is IRQ_RETURN.

.ifdef __ATARI__

IRQ_VECTOR              = $0216                     ; VIMIRQ
PBI_LATCH               = $D1FF                     ; PBI device select (write)
SHPDVS                  = $0248                     ; OS shadow of $D1FF
VERA_PBI_BIT            = $80                       ; the card's PBI device bit

.macro  IRQ_ENTER
        pha
        txa
        pha
        tya
        pha
        lda #VERA_PBI_BIT
        sta PBI_LATCH
.endmacro

.macro  IRQ_CHAIN old
        lda SHPDVS
        sta PBI_LATCH
        pla
        tay
        pla
        tax
        pla
        jmp old
.endmacro

.macro  IRQ_RETURN
        lda SHPDVS
        sta PBI_LATCH
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
        jmp old
.endmacro

.macro  IRQ_RETURN
        jmp $EA81                                   ; pla tay pla tax pla rti
.endmacro

.elseif .defined(__CX16__)

IRQ_VECTOR              = $0314                     ; CINV

.macro  IRQ_ENTER
.endmacro

.macro  IRQ_CHAIN old
        jmp old
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
        jmp old                                     ; VSYNC: the KERNAL too
ret:    IRQ_RETURN
.endmacro

.elseif .defined(__APPLE2__)

IRQ_VECTOR              = $03FE                     ; the Monitor's user IRQ vector
IRQ_A_SAVE              = $45                       ; A, saved by the IRQ entry

.macro  IRQ_ENTER
        lda IRQ_A_SAVE
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
        pla                                         ; ($45 still holds it)
        jmp old
.endmacro

.macro  IRQ_RETURN
        pla
        tay
        pla
        tax
        pla
        rti
.endmacro

.macro  IRQ_HOST_INSTALL
        .import plat_irq_lc
        jsr plat_irq_lc
.endmacro

.else
.error "libvera: unsupported target (ca65 -t atari, -t c64, -t cx16 or -t apple2)"
.endif

.ifndef __APPLE2__
.macro  IRQ_HOST_INSTALL
.endmacro
.endif

.ifndef __CX16__
.macro  IRQ_OURS_END old, pending
        IRQ_RETURN
.endmacro
.endif
