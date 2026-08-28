;
; zmem.asm - resident dynamic-memory access for the Z-machine
;
; This module deliberately does not implement high-memory I/O. Callers can
; detect DF=1 and route those reads through a file-backed cache later.
;

#include    include/opcodes.def

            extrn   zmbase
            extrn   zmend

            extrn   zmread
            extrn   zmwrite

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

; zmread16: RD = guest address. Returns RF = big-endian word (the
; format every V3 word field -- globals, property values, branch/call
; addresses -- is actually stored in). DF=1 if either byte is non-
; resident (the high byte is checked first; on DF=1 from that byte,
; the low byte is never read).
            proc    zmread16
            mov     r7, rd
            add16   r7, 1               ; r7 = the low byte's address
                                        ; -- untouched by zmread, so it
                                        ; survives both calls below
            call    zmread              ; d = high byte (rd unchanged)
            lbdf    zmr16_fail
            plo     rc                  ; rc.0 = high byte -- rc is
                                        ; untouched by zmread too

            mov     rd, r7
            call    zmread              ; d = low byte
            lbdf    zmr16_fail
            plo     rf                  ; rf.0 = low byte
            glo     rc
            phi     rf                  ; rf.1 = high byte -- rf is
                                        ; now the assembled word
            clc
            rtn
zmr16_fail:
            stc
            rtn
            endp

; zmwrite16: RD = guest address, RF = big-endian word. DF=1 if either
; byte is non-resident (the high byte is checked/written first; on
; DF=1 from that byte, the low byte is never touched).
            proc    zmwrite16
            mov     r7, rd
            add16   r7, 1               ; r7 = the low byte's address --
                                        ; untouched by zmwrite, so it
                                        ; survives both calls below
            ghi     rf
            plo     rc                  ; rc.0 = high byte
            glo     rf
            phi     rc                  ; rc.1 = low byte -- rc is also
                                        ; untouched by zmwrite, so both
                                        ; bytes survive its first call
                                        ; below even though that call's
                                        ; own RF.0 parameter overwrites
                                        ; the original rf

            glo     rc
            plo     rf
            call    zmwrite             ; writes the high byte at rd
                                        ; (the original address)
            lbdf    zmw16_fail

            mov     rd, r7
            ghi     rc
            plo     rf
            call    zmwrite             ; writes the low byte at r7
            lbdf    zmw16_fail
            clc
            rtn
zmw16_fail:
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
