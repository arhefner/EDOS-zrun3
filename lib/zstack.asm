;
; zstack.asm - bounded Z-machine evaluation stack primitive
;
; This is a reusable library module, not a standalone ELF-DOS program.
;

#include    include/opcodes.def

            extrn   zsbase
            extrn   zsptr
            extrn   zstop

; zstack_init: RD = first usable byte, RF = exclusive end.
            proc    zstack_init
            mov     rb, zsbase
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zsptr
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zstop
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            clc
            rtn
            endp

; zstack_push: RF = value. DF=1 if the value does not fit.
            proc    zstack_push
            mov     rb, zsptr
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; R8 = current stack pointer
            mov     r9, r8
            add16   r9, 2               ; R9 = pointer after new word
            mov     rb, zstop
            lda     rb
            phi     rd
            ldn     rb
            plo     rd                  ; RD = exclusive stack limit
            glo     r9
            str     r2
            glo     rd
            sm
            ghi     r9
            str     r2
            ghi     rd
            smb                         ; rd - r9 = top - R9; the 1802's
                                        ; SM/SMB set DF=1 for NO borrow, so
                                        ; DF=1 here means top >= R9 (still
                                        ; in bounds) and DF=0 means R9 has
                                        ; run past top -- overflow
            lbnf    zstack_push_fail
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8
            mov     rb, zsptr
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb
            clc
            rtn

zstack_push_fail:
            stc
            rtn
            endp

; zstack_pop: returns RF = value. DF=1 if empty.
            proc    zstack_pop
            mov     rb, zsptr
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; R8 = current stack pointer
            mov     rd, zsbase
            lda     rd
            phi     r9
            ldn     rd
            plo     r9                  ; R9 = first usable byte
            mov     rb, r8
            sub16   rb, 2               ; RB = candidate new pointer
            glo     r9
            str     r2
            glo     rb
            sm
            ghi     r9
            str     r2
            ghi     rb
            smb                         ; rb - r9 = candidate - base; the
                                        ; 1802's SM/SMB set DF=1 for NO
                                        ; borrow, so DF=1 here means
                                        ; candidate >= base (still valid)
                                        ; and DF=0 means candidate fell
                                        ; below base -- underflow
            lbnf    zstack_pop_fail
            mov     r8, rb              ; R8 = a disposable copy of the
                                        ; candidate pointer to read the
                                        ; value through -- lda advances
                                        ; whatever register it's given,
                                        ; and RB itself (the real new
                                        ; zsptr) must stay unchanged
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            mov     r9, zsptr
            ghi     rb
            str     r9
            inc     r9
            glo     rb
            str     r9
            clc
            rtn

zstack_pop_fail:
            stc
            rtn
            endp

            proc    _zstack_data
zsbase:     dw      0
zsptr:      dw      0
zstop:      dw      0
            public  zsbase
            public  zsptr
            public  zstop
            endp
