;
; zdecdiag.asm - self-contained diagnostic dispatch for the Z-text
; decoder (zdec.asm)
;
; check 0 reuses the exact "hello" byte sequence from
; tests/test_host.c's own ztext_decode test, cross-checked with a
; Python script; checks 1-2 (uppercase shift, punctuation shift) and
; the byte sequences for all of them were independently computed and
; verified the same way, not just eyeballed. Touches no ELF-DOS kernel
; or BIOS entry points. See diag/zdiag.asm for the analogous zmem/
; zstack diagnostic this mirrors.
;

#include    include/opcodes.def

            extrn   zdec_decode

            extrn   zd_hello_packed
            extrn   zd_hi_packed
            extrn   zd_punct_packed
            extrn   zd_bad_packed
            extrn   zd_outbuf
            extrn   zd_results

ZDECDIAG_COUNT: equ     4

            proc    zddiag_run

; check 0: "hello" (5 lowercase letters, one word of padding)
            mov     rd, zd_hello_packed
            mov     rf, zd_outbuf
            mov     rc, 4
            call    zdec_decode
            lbdf    zd_fail0
            mov     rf, zd_outbuf
            ldn     rf
            xri     'h'
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     'e'
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     'l'
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     'l'
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     'o'
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            lbnz    zd_fail0            ; NUL-terminated
            mov     rb, zd_results+0
            ldi     0
            lbr     zd_store0
zd_fail0:   mov     rb, zd_results+0
            ldi     1
zd_store0:  str     rb

; check 1: "Hi" (an uppercase letter via the A1 shift, then lowercase)
            mov     rd, zd_hi_packed
            mov     rf, zd_outbuf
            mov     rc, 4
            call    zdec_decode
            lbdf    zd_fail1
            mov     rf, zd_outbuf
            ldn     rf
            xri     'H'
            lbnz    zd_fail1
            inc     rf
            ldn     rf
            xri     'i'
            lbnz    zd_fail1
            inc     rf
            ldn     rf
            lbnz    zd_fail1
            mov     rb, zd_results+1
            ldi     0
            lbr     zd_store1
zd_fail1:   mov     rb, zd_results+1
            ldi     1
zd_store1:  str     rb

; check 2: "4!" (digit and punctuation via the A2 shift)
            mov     rd, zd_punct_packed
            mov     rf, zd_outbuf
            mov     rc, 4
            call    zdec_decode
            lbdf    zd_fail2
            mov     rf, zd_outbuf
            ldn     rf
            xri     '4'
            lbnz    zd_fail2
            inc     rf
            ldn     rf
            xri     '!'
            lbnz    zd_fail2
            inc     rf
            ldn     rf
            lbnz    zd_fail2
            mov     rb, zd_results+2
            ldi     0
            lbr     zd_store2
zd_fail2:   mov     rb, zd_results+2
            ldi     1
zd_store2:  str     rb

; check 3: z-char 1 (an abbreviation reference) is unsupported and
; reported as an error
            mov     rd, zd_bad_packed
            mov     rf, zd_outbuf
            mov     rc, 2
            call    zdec_decode
            lbnf    zd_fail3
            mov     rb, zd_results+3
            ldi     0
            lbr     zd_store3
zd_fail3:   mov     rb, zd_results+3
            ldi     1
zd_store3:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zd_results
            ldi     ZDECDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zd_tally:
            lda     rb
            lbz     zd_tally_next
            inc     rf
zd_tally_next:
            dec     r9
            glo     r9
            lbnz    zd_tally
            glo     rf
            lbnz    zd_fail_return
            clc
            rtn
zd_fail_return:
            stc
            rtn
            endp

            proc    _zdecdiag_data
zd_hello_packed:    db      $35,$51,$c6,$85
zd_hi_packed:       db      $11,$ae,$94,$a5
zd_punct_packed:    db      $15,$65,$cc,$a5
zd_bad_packed:      db      $84,$a5
zd_outbuf:          ds      8
zd_results:         ds      ZDECDIAG_COUNT
                public  zd_hello_packed
                public  zd_hi_packed
                public  zd_punct_packed
                public  zd_bad_packed
                public  zd_outbuf
                public  zd_results
            endp
