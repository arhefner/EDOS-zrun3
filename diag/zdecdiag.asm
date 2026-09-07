;
; zdecdiag.asm - self-contained diagnostic dispatch for the Z-text
; decoder (zdec.asm)
;
; check 0 reuses the exact "hello" byte sequence from
; tests/test_host.c's own ztext_decode test, cross-checked with a
; Python script; checks 1-2 (uppercase shift, punctuation shift) and
; the byte sequences for all of them were independently computed and
; verified the same way, not just eyeballed. Touches no ELF-DOS kernel
; or BIOS entry points, even checks 4-5 below (which call zminit --
; itself kernel-independent, same as diag/zdiag.asm's own use of it --
; so an abbreviation's table/text lookup resolves through zmread's
; RESIDENT path with no cache/kernel involvement at all). See
; diag/zdiag.asm for the analogous zmem/zstack diagnostic this mirrors.
;

#include    include/opcodes.def

            extrn   zdec_decode
            extrn   zdec_init
            extrn   zminit

            extrn   zd_hello_packed
            extrn   zd_hi_packed
            extrn   zd_punct_packed
            extrn   zd_bad_packed
            extrn   zd_abbrev_main
            extrn   zd_mem4
            extrn   zd_mem5
            extrn   zd_outbuf
            extrn   zd_results

ZDECDIAG_COUNT: equ     6

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

; check 2: "4" + newline + "!" (digit, the A2 newline, and punctuation,
; all via the A2 shift). The newline (z-char 7) is deliberately in the
; middle: zdec_a2 used to have no entry for it at all, which shifted
; every digit and every punctuation mark one z-char early -- this
; vector's old form ($15,$65,$cc,$a5) encoded '4' and '!' at those
; wrong indices, so it passed against the broken table and would pass
; again if the entry were ever dropped. Under the corrected table the
; old bytes decode to "3," instead.
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
            xri     10
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

; check 3: z-char 1 (an abbreviation reference) still fails cleanly
; (DF=1) when no abbreviation table has ever been configured (zdec_
; init never called in this run, zminit never called either) --
; zdec_abbrev_table defaults to 0 and zmread's own cache-uninitialized
; guard (zcfcb == 0) reports the resulting out-of-range lookup as a
; clean failure rather than a wild kernel call, exactly the same
; safety net proven in lib/zmem.asm's own zcache wild-pointer fix, now
; exercised for the first time from an abbreviation lookup instead of
; a resident-memory bounds check. This is NOT testing "abbreviations
; are unsupported" any more -- see checks 4-5 below for real
; expansion.
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

; check 4: real abbreviation expansion -- zd_abbrev_main encodes
; "x" + abbrev(0) + "y"; abbreviation index 0's table entry (at guest
; 16-17, packed addr 0x0c) points at guest byte address 24, itself
; "hi" ($b5,$c5, reusing zd_hi_packed's own already-verified encoding
; pattern) -- expected output "xhiy".
            mov     rd, zd_mem4
            mov     rf, 32
            call    zminit
            mov     rd, 16
            call    zdec_init

            mov     rd, zd_abbrev_main
            mov     rf, zd_outbuf
            mov     rc, 4
            call    zdec_decode
            lbdf    zd_fail4
            mov     rf, zd_outbuf
            ldn     rf
            xri     'x'
            lbnz    zd_fail4
            inc     rf
            ldn     rf
            xri     'h'
            lbnz    zd_fail4
            inc     rf
            ldn     rf
            xri     'i'
            lbnz    zd_fail4
            inc     rf
            ldn     rf
            xri     'y'
            lbnz    zd_fail4
            inc     rf
            ldn     rf
            lbnz    zd_fail4            ; NUL-terminated
            mov     rb, zd_results+4
            ldi     0
            lbr     zd_store4
zd_fail4:   mov     rb, zd_results+4
            ldi     1
zd_store4:  str     rb

; check 5: same table/main text as check 4, but the abbreviation's own
; target text ($84,$05 -- z-char 1, index byte 0, end) is itself
; another abbreviation reference -- must fail (DF=1), not expand a
; second level, per the Z-machine standard.
            mov     rd, zd_mem5
            mov     rf, 32
            call    zminit
            mov     rd, 16
            call    zdec_init

            mov     rd, zd_abbrev_main
            mov     rf, zd_outbuf
            mov     rc, 4
            call    zdec_decode
            lbnf    zd_fail5
            mov     rb, zd_results+5
            ldi     0
            lbr     zd_store5
zd_fail5:   mov     rb, zd_results+5
            ldi     1
zd_store5:  str     rb

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
zd_punct_packed:    db      $15,$85,$9c,$b4     ; "4"+newline+"!"
zd_bad_packed:      db      $84,$a5
zd_abbrev_main:     db      $74,$20,$f8,$a5     ; "x"+abbrev(0)+"y"
zd_mem4:            ds      16                  ; guest 0-15: unused
                                                ; padding
                    db      $00,$0c             ; guest 16-17: abbrev
                                                ; table entry 0 =
                                                ; packed addr 0x0c ->
                                                ; byte addr 24
                    ds      6                   ; guest 18-23: padding
                    db      $b5,$c5             ; guest 24-25: "hi",
                                                ; end=1 (reuses
                                                ; zd_hi_packed's own
                                                ; already-verified
                                                ; encoding)
                    ds      6                   ; pad zminit's own
                                                ; 32-byte request
zd_mem5:            ds      16
                    db      $00,$0c
                    ds      6
                    db      $84,$05             ; guest 24-25: z-char
                                                ; 1,0,5,end -- another
                                                ; abbreviation
                                                ; reference (invalid
                                                ; nested)
                    ds      6
zd_outbuf:          ds      8
zd_results:         ds      ZDECDIAG_COUNT
                public  zd_hello_packed
                public  zd_hi_packed
                public  zd_punct_packed
                public  zd_bad_packed
                public  zd_abbrev_main
                public  zd_mem4
                public  zd_mem5
                public  zd_outbuf
                public  zd_results
            endp
