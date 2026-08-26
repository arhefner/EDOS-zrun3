;
; zmem.asm - resident dynamic-memory access for the Z-machine
;
; This module deliberately does not implement high-memory I/O. Callers can
; detect DF=1 and route those reads through a file-backed cache later.
;

#include    include/opcodes.def

            extrn   zmbase
            extrn   zmend

; zminit: RD = host RAM base, RF = exclusive guest dynamic end.
            proc    zminit
            mov     rb, zmbase
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zmend
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            clc
            rtn
            endp

; zmread: RD = guest address, returns D = byte. DF=1 if non-resident.
            proc    zmread
            mov     rb, zmend
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, rd
            sub16   rb, r8              ; rb = address - zmend; the 1802's
                                        ; SM/SMB set DF=1 for NO borrow
                                        ; (minuend >= subtrahend), so DF=1
                                        ; here means address >= zmend --
                                        ; out of range
            lbdf    zmrf
            mov     rf, zmbase
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, rd
            add16   rf, r9
            ldn     rf
            clc
            rtn
zmrf:
            stc
            rtn
            endp

; zmwrite: RD = guest address, RF.0 = byte. DF=1 if non-resident.
            proc    zmwrite
            plo     r9
            mov     rb, zmend
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, rd
            sub16   rb, r8              ; rb = address - zmend; DF=1 (no
                                        ; borrow) means address >= zmend --
                                        ; out of range (see zmread)
            lbdf    zmwf
            mov     rf, zmbase
            lda     rf
            phi     r8
            ldn     rf
            plo     r8
            mov     rf, rd
            add16   rf, r8
            glo     r9
            str     rf
            clc
            rtn
zmwf:
            stc
            rtn
            endp

            proc    _zmem_data
zmbase:     dw      0
zmend:      dw      0
            public  zmbase
            public  zmend
            endp
