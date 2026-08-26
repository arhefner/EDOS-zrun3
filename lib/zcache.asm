;
; zcache.asm - one-window file-backed story-memory cache
;
#include    include/opcodes.def
#include    include/kernel_api.inc

            extrn   zcfcb
            extrn   zcbuf
            extrn   zcbase_hi
            extrn   zcbase_lo
            extrn   zccount
            extrn   zcvalid
            extrn   zcreq_hi
            extrn   zcreq_lo

; zcinit: RD = open story FCB, RF = 512-byte cache buffer.
            proc    zcinit
            mov     rb, zcfcb
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zcbuf
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            mov     rb, zcvalid
            ldi     0
            str     rb
            clc
            rtn
            endp

; zcread: RD = physical offset high word, RF = low word.
; Returns D = byte and DF=0, or DF=1 at EOF/I/O failure.
            proc    zcread
            mov     rb, zcreq_hi
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zcreq_lo
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            mov     rb, zcvalid
            ldn     rb
            lbz     zcmiss
            mov     rb, zcreq_hi
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, zcbase_hi
            lda     rb
            phi     r9
            ldn     rb
            plo     r9
            glo     r8
            str     r2
            glo     r9
            xor
            lbnz    zcmiss
            ghi     r8
            str     r2
            ghi     r9
            xor
            lbnz    zcmiss
            mov     rb, zcreq_lo
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, zcbase_lo
            lda     rb
            phi     r9
            ldn     rb
            plo     r9
            mov     rb, r8
            sub16   rb, r9              ; rb = req_lo - base_lo; the
                                        ; 1802's SM/SMB set DF=1 for NO
                                        ; borrow, so DF=0 here means
                                        ; req_lo < base_lo -- before the
                                        ; window, a miss
            lbnf    zcmiss

zchit_offset:
            mov     r8, rb
            mov     rb, zccount
            lda     rb
            phi     r9
            ldn     rb
            plo     r9
            mov     rb, r8
            sub16   rb, r9              ; rb = offset - zccount; DF=1 (no
                                        ; borrow) means offset >= zccount
                                        ; -- past the valid bytes in this
                                        ; window, a miss
            lbdf    zcmiss

zchit_byte:
            mov     rf, zcbuf
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, r9
            add16   rf, r8
            ldn     rf
            clc
            rtn

zcmiss:
            mov     rb, zcreq_hi
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, zcreq_lo
            lda     rb
            phi     r9
            ldn     rb
            plo     r9
            ghi     r9
            ani     $fe
            phi     r9
            ldi     0
            plo     r9
            mov     rb, zcbase_hi
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb
            mov     rb, zcbase_lo
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb
            mov     rb, zcfcb
            lda     rb
            phi     rd
            ldn     rb
            plo     rd
            mov     ra, r8
            mov     r9, r9
            ldi     0
            plo     rc
            phi     rc
            call    K_FILE_SEEK
            lbdf    zciofail
            mov     rb, zcfcb
            lda     rb
            phi     rd
            ldn     rb
            plo     rd
            mov     rb, zcbuf
            lda     rb
            phi     rf
            ldn     rb
            plo     rf
            ldi     2
            phi     rc
            ldi     0
            plo     rc
            call    K_FILE_READ
            lbdf    zciofail
            mov     rb, zccount
            ghi     rc
            str     rb
            inc     rb
            glo     rc
            str     rb
            mov     rb, zcvalid
            ldi     1
            str     rb
            mov     rb, zcreq_lo
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, zcbase_lo
            lda     rb
            phi     r9
            ldn     rb
            plo     r9
            mov     rb, r8
            sub16   rb, r9
            lbr     zchit_offset

zciofail:
            mov     rb, zcvalid
            ldi     0
            str     rb
            stc
            rtn
            endp

            proc    zcdata
zcfcb:      dw      0
zcbuf:      dw      0
zcbase_hi: dw      0
zcbase_lo: dw      0
zcreq_hi:   dw      0
zcreq_lo:   dw      0
zccount:    dw      0
zcvalid:    dw      0
            public  zcfcb
            public  zcbuf
            public  zcbase_hi
            public  zcbase_lo
            public  zccount
            public  zcvalid
            public  zcreq_hi
            public  zcreq_lo
            endp
