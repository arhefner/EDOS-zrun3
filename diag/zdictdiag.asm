;
; zdictdiag.asm - self-contained diagnostic dispatch for the
; dictionary primitives (zdict.asm)
;
; Uses the exact same 3-entry dictionary ("cat"/"dog"/"run") as
; tests/test_host.c's own dictionary test, with the encoded word bytes
; hand-verified (and cross-checked with a Python script) rather than
; produced by the encoder itself, so the encoder and the dictionary
; table are independent of each other here. Touches no ELF-DOS kernel
; or BIOS entry points. See diag/zdiag.asm for the analogous zmem/
; zstack diagnostic this mirrors.
;

#include    include/opcodes.def

            extrn   zdict_init
            extrn   zdict_encode
            extrn   zdict_lookup
            extrn   zdict_find_word

            extrn   zt_dict
            extrn   zt_cat
            extrn   zt_dog
            extrn   zt_run
            extrn   zt_xyz
            extrn   zt_alphabet
            extrn   zt_bad
            extrn   zt_encbuf
            extrn   zt_encbuf2
            extrn   zt_results

ZDICTDIAG_COUNT:        equ     7

            proc    zddiag_run
            mov     rd, zt_dict
            mov     rf, zt_dict              ; guest address == real
                                        ; address here: this
                                        ; diagnostic's fake
                                        ; dictionary is checked
                                        ; through real pointers
                                        ; throughout
            call    zdict_init

; check 0: encoding "cat" produces the exact expected bytes
            mov     rd, zt_cat
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            lbdf    zd_fail0
            mov     rf, zt_encbuf
            ldn     rf
            xri     $20
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     $d9
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     $94
            lbnz    zd_fail0
            inc     rf
            ldn     rf
            xri     $a5
            lbnz    zd_fail0
            mov     rb, zt_results+0
            ldi     0
            lbr     zd_store0
zd_fail0:   mov     rb, zt_results+0
            ldi     1
zd_store0:  str     rb

; check 1: an 8-character word truncates to the same 4 bytes as its
; own first 6 characters -- AND to the exact bytes those 6 characters
; must produce. The exact-bytes half matters: comparing two encodings
; of the same word against each other alone passed happily while the
; encoder was silently stopping one z-char early (see zdict_encode's
; own zde_check_fit fix), since both sides truncated identically.
            mov     rd, zt_alphabet
            mov     rf, zt_encbuf
            ldi     8
            call    zdict_encode
            lbdf    zd_fail1
            mov     rd, zt_alphabet
            mov     rf, zt_encbuf2
            ldi     6
            call    zdict_encode
            lbdf    zd_fail1
            mov     r8, zt_encbuf
            mov     r9, zt_encbuf2
            ldn     r8
            str     r2
            ldn     r9
            xor
            lbnz    zd_fail1
            inc     r8
            inc     r9
            ldn     r8
            str     r2
            ldn     r9
            xor
            lbnz    zd_fail1
            inc     r8
            inc     r9
            ldn     r8
            str     r2
            ldn     r9
            xor
            lbnz    zd_fail1
            inc     r8
            inc     r9
            ldn     r8
            str     r2
            ldn     r9
            xor
            lbnz    zd_fail1

            ; "alphab" -> z-chars 6,17,21,13,6,7 -> $1a,$35,$b4,$c7
            mov     r8, zt_encbuf
            lda     r8
            xri     $1a
            lbnz    zd_fail1
            lda     r8
            xri     $35
            lbnz    zd_fail1
            lda     r8
            xri     $b4
            lbnz    zd_fail1
            ldn     r8
            xri     $c7
            lbnz    zd_fail1

            mov     rb, zt_results+1
            ldi     0
            lbr     zd_store1
zd_fail1:   mov     rb, zt_results+1
            ldi     1
zd_store1:  str     rb

; check 2: a character outside a-z/A-Z/space/punctuation is rejected
            mov     rd, zt_bad
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            lbnf    zd_fail2
            mov     rb, zt_results+2
            ldi     0
            lbr     zd_store2
zd_fail2:   mov     rb, zt_results+2
            ldi     1
zd_store2:  str     rb

; check 3: "dog" is found at its known offset, with its data byte
; intact
            mov     rd, zt_dog
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            mov     rd, zt_encbuf
            call    zdict_lookup
            mov     r8, zt_dict
            add16   r8, 12
            mov     r9, rf
            sub16   r9, r8
            glo     r9
            lbnz    zd_fail3
            ghi     r9
            lbnz    zd_fail3
            add16   rf, 4
            ldn     rf
            xri     $dd
            lbnz    zd_fail3
            mov     rb, zt_results+3
            ldi     0
            lbr     zd_store3
zd_fail3:   mov     rb, zt_results+3
            ldi     1
zd_store3:  str     rb

; check 4: "cat" and "run" are found at their own known offsets
            mov     rd, zt_cat
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            mov     rd, zt_encbuf
            call    zdict_lookup
            mov     r8, zt_dict
            add16   r8, 5
            mov     r9, rf
            sub16   r9, r8
            glo     r9
            lbnz    zd_fail4
            ghi     r9
            lbnz    zd_fail4

            mov     rd, zt_run
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            mov     rd, zt_encbuf
            call    zdict_lookup
            mov     r8, zt_dict
            add16   r8, 19
            mov     r9, rf
            sub16   r9, r8
            glo     r9
            lbnz    zd_fail4
            ghi     r9
            lbnz    zd_fail4

            mov     rb, zt_results+4
            ldi     0
            lbr     zd_store4
zd_fail4:   mov     rb, zt_results+4
            ldi     1
zd_store4:  str     rb

; check 5: a word that isn't in the dictionary reports address 0
            mov     rd, zt_xyz
            mov     rf, zt_encbuf
            ldi     3
            call    zdict_encode
            mov     rd, zt_encbuf
            call    zdict_lookup
            glo     rf
            lbnz    zd_fail5
            ghi     rf
            lbnz    zd_fail5
            mov     rb, zt_results+5
            ldi     0
            lbr     zd_store5
zd_fail5:   mov     rb, zt_results+5
            ldi     1
zd_store5:  str     rb

; check 6: zdict_find_word combines encoding and lookup in one call
            mov     rd, zt_dog
            ldi     3
            call    zdict_find_word
            lbdf    zd_fail6
            mov     r8, zt_dict
            add16   r8, 12
            mov     r9, rf
            sub16   r9, r8
            glo     r9
            lbnz    zd_fail6
            ghi     r9
            lbnz    zd_fail6
            mov     rb, zt_results+6
            ldi     0
            lbr     zd_store6
zd_fail6:   mov     rb, zt_results+6
            ldi     1
zd_store6:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zt_results
            ldi     ZDICTDIAG_COUNT
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

            proc    _zdictdiag_data
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

zt_cat:         db      "cat"
zt_dog:         db      "dog"
zt_run:         db      "run"
zt_xyz:         db      "xyz"
zt_alphabet:    db      "alphabet"
zt_bad:         db      "h@i"
zt_encbuf:      ds      4
zt_encbuf2:     ds      4
zt_results:     ds      ZDICTDIAG_COUNT
                public  zt_dict
                public  zt_cat
                public  zt_dog
                public  zt_run
                public  zt_xyz
                public  zt_alphabet
                public  zt_bad
                public  zt_encbuf
                public  zt_encbuf2
                public  zt_results
            endp
