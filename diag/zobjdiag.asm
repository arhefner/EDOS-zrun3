;
; zobjdiag.asm - self-contained diagnostic dispatch for the object
; tree and attribute primitives (zobj.asm)
;
; Builds a small private 3-object tree and exercises tree queries,
; attribute flags, and remove/insert tree surgery. Touches no ELF-DOS
; kernel or BIOS entry points. See diag/zdiag.asm for the analogous
; zmem/zstack diagnostic this mirrors.
;

#include    include/opcodes.def

            extrn   zobj_init
            extrn   zobj_get_parent
            extrn   zobj_get_sibling
            extrn   zobj_get_child
            extrn   zobj_test_attr
            extrn   zobj_set_attr
            extrn   zobj_clear_attr
            extrn   zobj_remove
            extrn   zobj_insert
            extrn   zobj_short_name

            extrn   zo_table
            extrn   zo_results

ZODIAG_COUNT:   equ     6

; zodiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zo_results[0..ZODIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail), in the order described below.
            proc    zodiag_run
            mov     rd, zo_table
            call    zobj_init

; check 0: initial tree shape -- object 1 is the parent of object 2,
; whose sibling is object 3
            mov     rd, 1
            call    zobj_get_child
            xri     2
            lbnz    zo_fail0
            mov     rd, 2
            call    zobj_get_parent
            xri     1
            lbnz    zo_fail0
            mov     rd, 2
            call    zobj_get_sibling
            xri     3
            lbnz    zo_fail0
            mov     rb, zo_results+0
            ldi     0
            lbr     zo_store0
zo_fail0:   mov     rb, zo_results+0
            ldi     1
zo_store0:  str     rb

; check 1: attribute 3 on object 3 starts clear, can be set and
; cleared again
            mov     rd, 3
            ldi     3
            call    zobj_test_attr
            lbdf    zo_fail1
            mov     rd, 3
            ldi     3
            call    zobj_set_attr
            mov     rd, 3
            ldi     3
            call    zobj_test_attr
            lbnf    zo_fail1
            mov     rd, 3
            ldi     3
            call    zobj_clear_attr
            mov     rd, 3
            ldi     3
            call    zobj_test_attr
            lbdf    zo_fail1
            mov     rb, zo_results+1
            ldi     0
            lbr     zo_store1
zo_fail1:   mov     rb, zo_results+1
            ldi     1
zo_store1:  str     rb

; check 2: attribute 31 (top bit of the last byte) doesn't disturb
; attribute 3 (top bit of the first byte)
            mov     rd, 3
            ldi     3
            call    zobj_set_attr
            mov     rd, 3
            ldi     31
            call    zobj_set_attr
            mov     rd, 3
            ldi     3
            call    zobj_test_attr
            lbnf    zo_fail2
            mov     rd, 3
            ldi     31
            call    zobj_test_attr
            lbnf    zo_fail2
            mov     rd, 3
            ldi     3
            call    zobj_clear_attr
            mov     rd, 3
            ldi     31
            call    zobj_clear_attr
            mov     rd, 3
            ldi     3
            call    zobj_test_attr
            lbdf    zo_fail2
            mov     rb, zo_results+2
            ldi     0
            lbr     zo_store2
zo_fail2:   mov     rb, zo_results+2
            ldi     1
zo_store2:  str     rb

; check 3: removing object 2 (the first child) promotes its sibling
; (object 3) to be object 1's child, and detaches object 2
            mov     rd, 2
            call    zobj_remove
            lbdf    zo_fail3
            mov     rd, 1
            call    zobj_get_child
            xri     3
            lbnz    zo_fail3
            mov     rd, 2
            call    zobj_get_parent
            lbnz    zo_fail3
            mov     rb, zo_results+3
            ldi     0
            lbr     zo_store3
zo_fail3:   mov     rb, zo_results+3
            ldi     1
zo_store3:  str     rb

; check 4: inserting object 2 under object 3 makes it object 3's only
; child, with no leftover sibling
            mov     rd, 2
            ldi     3
            call    zobj_insert
            mov     rd, 2
            call    zobj_get_parent
            xri     3
            lbnz    zo_fail4
            mov     rd, 3
            call    zobj_get_child
            xri     2
            lbnz    zo_fail4
            mov     rd, 2
            call    zobj_get_sibling
            lbnz    zo_fail4
            mov     rb, zo_results+4
            ldi     0
            lbr     zo_store4
zo_fail4:   mov     rb, zo_results+4
            ldi     1
zo_store4:  str     rb

; check 5: zobj_short_name reports the property table's text address
; (one byte past the table start) and length (word_count * 2) for
; object 1's 1-word short name
            mov     rd, 1
            call    zobj_short_name     ; rf = addr, rc = length
            mov     r8, zo_table
            add16   r8, 101
            mov     r9, rf
            sub16   r9, r8
            glo     r9
            lbnz    zo_fail5
            ghi     r9
            lbnz    zo_fail5
            glo     rc
            xri     2
            lbnz    zo_fail5
            mov     rb, zo_results+5
            ldi     0
            lbr     zo_store5
zo_fail5:   mov     rb, zo_results+5
            ldi     1
zo_store5:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zo_results
            ldi     ZODIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zo_tally:
            lda     rb
            lbz     zo_tally_next
            inc     rf
zo_tally_next:
            dec     r9
            glo     r9
            lbnz    zo_tally
            glo     rf
            lbnz    zo_fail_return
            clc
            rtn
zo_fail_return:
            stc
            rtn
            endp

            proc    _zobjdiag_data
zo_table:
                ds      62                  ; property defaults (unused
                                            ; by this diagnostic)
; object 1: child = 2
                db      0,0,0,0
                db      0                   ; parent
                db      0                   ; sibling
                db      2                   ; child
                dw      zo_table+100        ; property table address
; object 2: parent = 1, sibling = 3
                db      0,0,0,0
                db      1
                db      3
                db      0
                dw      0                   ; property table (unused)
; object 3: parent = 1
                db      0,0,0,0
                db      1
                db      0
                db      0
                dw      0                   ; property table (unused)
                ds      11                  ; pad to offset 100
                db      1                   ; object 1: 1-word short name
zo_results:     ds      ZODIAG_COUNT
                public  zo_table
                public  zo_results
            endp
