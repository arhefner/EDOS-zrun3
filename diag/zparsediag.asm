;
; zparsediag.asm - self-contained diagnostic dispatch for the
; tokenizer (zparse.asm)
;
; Uses the exact same dictionary and "take cat, run" input text as
; tests/test_host.c's own parser test, so the two are directly
; comparable. Touches no ELF-DOS kernel or BIOS entry points. See
; diag/zdiag.asm for the analogous zmem/zstack diagnostic this
; mirrors.
;

#include    include/opcodes.def

            extrn   zdict_init
            extrn   zparse_init
            extrn   zparse_tokenize

            extrn   zt_dict
            extrn   zt_text
            extrn   zt_parse
            extrn   zt_results

ZPARSEDIAG_COUNT:       equ     5

            proc    zpdiag_run
            mov     rd, zt_dict
            call    zdict_init

            mov     rd, zt_text
            mov     rf, zt_parse
            ldi     13                  ; rc.0 = text length
            plo     rc
            ldi     2                   ; rc.1 = text offset
            phi     rc
            call    zparse_init

            call    zparse_tokenize
            lbdf    zp_fail0

; check 0: 4 words were found
            mov     rf, zt_parse
            add16   rf, 1
            ldn     rf
            xri     4
            lbnz    zp_fail0
            mov     rb, zt_results+0
            ldi     0
            lbr     zp_store0
zp_fail0:   mov     rb, zt_results+0
            ldi     1
zp_store0:  str     rb

; check 1: word 0 ("take") -- not in the dictionary, length 4,
; position 2
            mov     rf, zt_parse
            add16   rf, 2
            ldn     rf
            lbnz    zp_fail1
            inc     rf
            ldn     rf
            lbnz    zp_fail1
            inc     rf
            ldn     rf
            xri     4
            lbnz    zp_fail1
            inc     rf
            ldn     rf
            xri     2
            lbnz    zp_fail1
            mov     rb, zt_results+1
            ldi     0
            lbr     zp_store1
zp_fail1:   mov     rb, zt_results+1
            ldi     1
zp_store1:  str     rb

; check 2: word 1 ("cat") -- found at the dictionary's "cat" entry
; (zt_dict+5), length 3, position 7
            mov     rf, zt_parse
            add16   rf, 6
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = entry_addr
            mov     r9, zt_dict
            add16   r9, 5               ; r9 = expected entry address
            mov     ra, r8
            sub16   ra, r9
            glo     ra
            lbnz    zp_fail2
            ghi     ra
            lbnz    zp_fail2
            inc     rf
            ldn     rf
            xri     3
            lbnz    zp_fail2
            inc     rf
            ldn     rf
            xri     7
            lbnz    zp_fail2
            mov     rb, zt_results+2
            ldi     0
            lbr     zp_store2
zp_fail2:   mov     rb, zt_results+2
            ldi     1
zp_store2:  str     rb

; check 3: word 2 (",") -- the separator as its own token, not in the
; dictionary, length 1, position 10
            mov     rf, zt_parse
            add16   rf, 10
            ldn     rf
            lbnz    zp_fail3
            inc     rf
            ldn     rf
            lbnz    zp_fail3
            inc     rf
            ldn     rf
            xri     1
            lbnz    zp_fail3
            inc     rf
            ldn     rf
            xri     10
            lbnz    zp_fail3
            mov     rb, zt_results+3
            ldi     0
            lbr     zp_store3
zp_fail3:   mov     rb, zt_results+3
            ldi     1
zp_store3:  str     rb

; check 4: word 3 ("run") -- found at the dictionary's "run" entry
; (zt_dict+19), length 3, position 12
            mov     rf, zt_parse
            add16   rf, 14
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = entry_addr
            mov     r9, zt_dict
            add16   r9, 19              ; r9 = expected entry address
            mov     ra, r8
            sub16   ra, r9
            glo     ra
            lbnz    zp_fail4
            ghi     ra
            lbnz    zp_fail4
            inc     rf
            ldn     rf
            xri     3
            lbnz    zp_fail4
            inc     rf
            ldn     rf
            xri     12
            lbnz    zp_fail4
            mov     rb, zt_results+4
            ldi     0
            lbr     zp_store4
zp_fail4:   mov     rb, zt_results+4
            ldi     1
zp_store4:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zt_results
            ldi     ZPARSEDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zp_tally:
            lda     rb
            lbz     zp_tally_next
            inc     rf
zp_tally_next:
            dec     r9
            glo     r9
            lbnz    zp_tally
            glo     rf
            lbnz    zp_fail_return
            clc
            rtn
zp_fail_return:
            stc
            rtn
            endp

            proc    _zparsediag_data
zt_dict:
                db      1                     ; 1 separator character
                db      ','
                db      7                     ; 7 bytes per entry
                dw      3                     ; 3 entries
                db      $20,$d9,$94,$a5       ; "cat"
                db      $aa,$bb,$cc
                db      $26,$8c,$94,$a5       ; "dog"
                db      $dd,$ee,$ff
                db      $5f,$53,$94,$a5       ; "run"
                db      $11,$22,$33

zt_text:        db      "take cat, run"       ; 13 bytes, no header
zt_parse:       db      10                    ; max words
                ds      1                     ; word count (written)
                ds      16                    ; up to 4 word records
zt_results:     ds      ZPARSEDIAG_COUNT
                public  zt_dict
                public  zt_text
                public  zt_parse
                public  zt_results
            endp
