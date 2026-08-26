;
; ztermdiag.asm - self-contained diagnostic dispatch for
; zterm_lowercase, the one piece of zterm.asm with no kernel
; dependency. print_char/print_string/read_line themselves need the
; real ELF-DOS kernel (hardware or a full boot) to exercise -- see
; diag/ztermdiag_main.asm for an interactive program that checks those
; by hand. Touches no ELF-DOS kernel or BIOS entry points itself. See
; diag/zdiag.asm for the analogous zmem/zstack diagnostic this
; mirrors.
;

#include    include/opcodes.def

            extrn   zterm_lowercase

            extrn   zt_mixed
            extrn   zt_lower
            extrn   zt_symbols
            extrn   zt_empty
            extrn   zt_results

ZTERMDIAG_COUNT:        equ     4

            proc    ztdiag_run

; check 0: a mixed-case string lowercases correctly
            mov     rd, zt_mixed
            call    zterm_lowercase
            mov     rf, zt_mixed
            ldn     rf
            xri     'h'
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     'e'
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     'l'
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     'l'
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     'o'
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     ','
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     ' '
            lbnz    zt_fail0
            inc     rf
            ldn     rf
            xri     'w'
            lbnz    zt_fail0
            mov     rb, zt_results+0
            ldi     0
            lbr     zt_store0
zt_fail0:   mov     rb, zt_results+0
            ldi     1
zt_store0:  str     rb

; check 1: an already-lowercase string is unchanged
            mov     rd, zt_lower
            call    zterm_lowercase
            mov     rf, zt_lower
            ldn     rf
            xri     'a'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'l'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'r'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'e'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'a'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'd'
            lbnz    zt_fail1
            inc     rf
            ldn     rf
            xri     'y'
            lbnz    zt_fail1
            mov     rb, zt_results+1
            ldi     0
            lbr     zt_store1
zt_fail1:   mov     rb, zt_results+1
            ldi     1
zt_store1:  str     rb

; check 2: digits and punctuation are untouched
            mov     rd, zt_symbols
            call    zterm_lowercase
            mov     rf, zt_symbols
            ldn     rf
            xri     '4'
            lbnz    zt_fail2
            inc     rf
            ldn     rf
            xri     '2'
            lbnz    zt_fail2
            inc     rf
            ldn     rf
            xri     '!'
            lbnz    zt_fail2
            mov     rb, zt_results+2
            ldi     0
            lbr     zt_store2
zt_fail2:   mov     rb, zt_results+2
            ldi     1
zt_store2:  str     rb

; check 3: an empty string stays empty (and the call doesn't run off
; into adjacent memory)
            mov     rd, zt_empty
            call    zterm_lowercase
            mov     rf, zt_empty
            ldn     rf
            lbnz    zt_fail3
            mov     rb, zt_results+3
            ldi     0
            lbr     zt_store3
zt_fail3:   mov     rb, zt_results+3
            ldi     1
zt_store3:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zt_results
            ldi     ZTERMDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zt_tally:
            lda     rb
            lbz     zt_tally_next
            inc     rf
zt_tally_next:
            dec     r9
            glo     r9
            lbnz    zt_tally
            glo     rf
            lbnz    zt_fail_return
            clc
            rtn
zt_fail_return:
            stc
            rtn
            endp

            proc    _ztermdiag_data
zt_mixed:       db      "Hello, World!",0
zt_lower:       db      "already",0
zt_symbols:     db      "42!",0
zt_empty:       db      0
zt_results:     ds      ZTERMDIAG_COUNT
                public  zt_mixed
                public  zt_lower
                public  zt_symbols
                public  zt_empty
                public  zt_results
            endp
