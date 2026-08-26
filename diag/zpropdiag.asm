;
; zpropdiag.asm - self-contained diagnostic dispatch for the property
; primitives (zprop.asm)
;
; Builds the same 3-object/property layout as tests/test_host.c's own
; object/property test, so the two can be compared directly. Touches
; no ELF-DOS kernel or BIOS entry points. See diag/zdiag.asm for the
; analogous zmem/zstack diagnostic this mirrors.
;

#include    include/opcodes.def

            extrn   zobj_init
            extrn   zprop_get_addr
            extrn   zprop_get_len
            extrn   zprop_get
            extrn   zprop_get_next

            extrn   zp_table
            extrn   zp_results

ZPDIAG_COUNT:   equ     7

; zpdiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zp_results[0..ZPDIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail), in the order described below.
            proc    zpdiag_run
            mov     rd, zp_table
            call    zobj_init

; check 0: property 5 on object 1 has length 1 and a real address
            mov     rd, 1
            ldi     5
            call    zprop_get_addr
            glo     rf
            lbz     zp_fail0
            mov     rd, rf
            call    zprop_get_len
            xri     1
            lbnz    zp_fail0
            mov     rb, zp_results+0
            ldi     0
            lbr     zp_store0
zp_fail0:   mov     rb, zp_results+0
            ldi     1
zp_store0:  str     rb

; check 1: property 3 on object 1 has length 2 and a real address
            mov     rd, 1
            ldi     3
            call    zprop_get_addr
            glo     rf
            lbz     zp_fail1
            mov     rd, rf
            call    zprop_get_len
            xri     2
            lbnz    zp_fail1
            mov     rb, zp_results+1
            ldi     0
            lbr     zp_store1
zp_fail1:   mov     rb, zp_results+1
            ldi     1
zp_store1:  str     rb

; check 2: property 9 doesn't exist on object 1; its (absent) address
; reports length 0
            mov     rd, 1
            ldi     9
            call    zprop_get_addr
            glo     rf
            lbnz    zp_fail2
            ghi     rf
            lbnz    zp_fail2
            mov     rd, rf
            call    zprop_get_len
            lbnz    zp_fail2
            mov     rb, zp_results+2
            ldi     0
            lbr     zp_store2
zp_fail2:   mov     rb, zp_results+2
            ldi     1
zp_store2:  str     rb

; check 3: zprop_get returns property 5's byte and property 3's word
            mov     rd, 1
            ldi     5
            call    zprop_get
            glo     rf
            xri     $99
            lbnz    zp_fail3
            ghi     rf
            lbnz    zp_fail3
            mov     rd, 1
            ldi     3
            call    zprop_get
            ghi     rf
            xri     $12
            lbnz    zp_fail3
            glo     rf
            xri     $34
            lbnz    zp_fail3
            mov     rb, zp_results+3
            ldi     0
            lbr     zp_store3
zp_fail3:   mov     rb, zp_results+3
            ldi     1
zp_store3:  str     rb

; check 4: object 2 has no properties of its own, so property 7 comes
; back from the defaults table (0x2222)
            mov     rd, 2
            ldi     7
            call    zprop_get
            ghi     rf
            xri     $22
            lbnz    zp_fail4
            glo     rf
            xri     $22
            lbnz    zp_fail4
            mov     rb, zp_results+4
            ldi     0
            lbr     zp_store4
zp_fail4:   mov     rb, zp_results+4
            ldi     1
zp_store4:  str     rb

; check 5: property enumeration on object 1 visits 5, then 3, then 0
            mov     rd, 1
            ldi     0
            call    zprop_get_next
            xri     5
            lbnz    zp_fail5
            mov     rd, 1
            ldi     5
            call    zprop_get_next
            xri     3
            lbnz    zp_fail5
            mov     rd, 1
            ldi     3
            call    zprop_get_next
            lbnz    zp_fail5
            mov     rb, zp_results+5
            ldi     0
            lbr     zp_store5
zp_fail5:   mov     rb, zp_results+5
            ldi     1
zp_store5:  str     rb

; check 6: object 2 (no properties) enumerates straight to 0; asking
; for the property after a nonexistent one (9) reports an error
            mov     rd, 2
            ldi     0
            call    zprop_get_next
            lbnz    zp_fail6
            mov     rd, 1
            ldi     9
            call    zprop_get_next
            lbnf    zp_fail6
            mov     rb, zp_results+6
            ldi     0
            lbr     zp_store6
zp_fail6:   mov     rb, zp_results+6
            ldi     1
zp_store6:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zp_results
            ldi     ZPDIAG_COUNT
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

            proc    _zpropdiag_data
zp_table:
                db      0,0,0,0,0,0,0,0,0,0,0,0     ; defaults 1-6
                db      $22,$22                      ; default 7 (used
                                                     ; by check 4)
                ds      48                            ; defaults 8-31,
                                                       ; pad to offset 62
; object 1: child = 2, property table @ zp_table+100
                db      0,0,0,0
                db      0
                db      0
                db      2
                dw      zp_table+100
; object 2: parent = 1, sibling = 3, property table @ zp_table+110
                db      0,0,0,0
                db      1
                db      3
                db      0
                dw      zp_table+110
; object 3: parent = 1, property table @ zp_table+115
                db      0,0,0,0
                db      1
                db      0
                db      0
                dw      zp_table+115
                ds      11                            ; pad to offset 100

; object 1's property table: 1-word short name, then property 5
; (length 1, value $99), property 3 (length 2, value $1234)
                db      1                             ; word count
                db      $80,$00                       ; short name text
                db      $05,$99                       ; property 5
                db      $23,$12,$34                   ; property 3
                db      0                             ; end of list
                                                       ; (offset 109 --
                                                       ; one byte of pad
                                                       ; to reach 110)
                ds      1

; object 2's property table: no name, no properties
                db      0                             ; word count
                db      0                             ; end of list
                                                       ; (offset 112 --
                                                       ; pad to 115)
                ds      3

; object 3's property table: no name, property 5 (length 1, unused by
; these checks but present for parity with the host test)
                db      0                             ; word count
                db      $05,$42                       ; property 5
                db      0                             ; end of list

zp_results:     ds      ZPDIAG_COUNT
                public  zp_table
                public  zp_results
            endp
