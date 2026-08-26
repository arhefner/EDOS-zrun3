;
; zdiag.asm - self-contained diagnostic dispatch for zmem/zstack
;
; Runs a fixed table of checks against a private scratch region and
; records one 0 (pass)/1 (fail) byte per check in zdiag_results. Touches
; no ELF-DOS kernel or BIOS entry points, so it can run under a bare
; 1802 host (e.g. an emulator with no OS loaded) as well as inside a
; real ELF-DOS program. See diag/zdiag_main.asm for the ELF-DOS front
; end that reports these results through K_MSG.
;

#include    include/opcodes.def

            extrn   zminit
            extrn   zmread
            extrn   zmwrite
            extrn   zstack_init
            extrn   zstack_push
            extrn   zstack_pop

            extrn   zd_mem_buf
            extrn   zd_stack_buf
            extrn   zd_results

ZDIAG_COUNT:    equ     7

; zdiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zdiag_results[0..ZDIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail), in the order described below.
            proc    zdiag_run
            mov     rd, zd_mem_buf
            mov     rf, 8
            call    zminit              ; dynamic guest addresses 0..7

; check 0: zmwrite(3, $a5) succeeds and zmread(3) reads it back. Note
; zmwrite's actual calling convention is D = byte at call time (not RF
; itself, despite the doc comment in zmem.asm -- see project notes).
            mov     rd, 3
            ldi     $a5
            call    zmwrite
            lbdf    zd_fail0
            mov     rd, 3
            call    zmread
            xri     $a5
            lbnz    zd_fail0
            mov     rb, zd_results+0
            ldi     0
            lbr     zd_store0
zd_fail0:   mov     rb, zd_results+0
            ldi     1
zd_store0:  str     rb

; check 1: writes at the low and high end of the dynamic region land at
; distinct offsets and don't clobber each other
            mov     rd, 0
            ldi     $11
            call    zmwrite
            lbdf    zd_fail1
            mov     rd, 7
            ldi     $22
            call    zmwrite
            lbdf    zd_fail1
            mov     rd, 0
            call    zmread
            xri     $11
            lbnz    zd_fail1
            mov     rd, 7
            call    zmread
            xri     $22
            lbnz    zd_fail1
            mov     rb, zd_results+1
            ldi     0
            lbr     zd_store1
zd_fail1:   mov     rb, zd_results+1
            ldi     1
zd_store1:  str     rb

; check 2: zmwrite just past the dynamic end (address 8) is rejected
            mov     rd, 8
            ldi     0
            call    zmwrite
            lbnf    zd_fail2
            mov     rb, zd_results+2
            ldi     0
            lbr     zd_store2
zd_fail2:   mov     rb, zd_results+2
            ldi     1
zd_store2:  str     rb

; check 3: zmread just past the dynamic end is rejected the same way
            mov     rd, 8
            call    zmread
            lbnf    zd_fail3
            mov     rb, zd_results+3
            ldi     0
            lbr     zd_store3
zd_fail3:   mov     rb, zd_results+3
            ldi     1
zd_store3:  str     rb

            mov     rd, zd_stack_buf
            mov     rf, zd_stack_buf+8
            call    zstack_init         ; 4-word (8-byte) capacity

; check 4: two pushes come back off two pops in LIFO order
            mov     rf, $1234
            call    zstack_push
            lbdf    zd_fail4
            mov     rf, $5678
            call    zstack_push
            lbdf    zd_fail4
            call    zstack_pop
            lbdf    zd_fail4
            ghi     rf
            xri     $56
            lbnz    zd_fail4
            glo     rf
            xri     $78
            lbnz    zd_fail4
            call    zstack_pop
            lbdf    zd_fail4
            ghi     rf
            xri     $12
            lbnz    zd_fail4
            glo     rf
            xri     $34
            lbnz    zd_fail4
            mov     rb, zd_results+4
            ldi     0
            lbr     zd_store4
zd_fail4:   mov     rb, zd_results+4
            ldi     1
zd_store4:  str     rb

; check 5: the stack is empty again after check 4 -- popping it now
; must report underflow
            call    zstack_pop
            lbnf    zd_fail5
            mov     rb, zd_results+5
            ldi     0
            lbr     zd_store5
zd_fail5:   mov     rb, zd_results+5
            ldi     1
zd_store5:  str     rb

; check 6: four pushes fill the 4-word capacity; a fifth overflows
            mov     rf, $1111
            call    zstack_push
            lbdf    zd_fail6
            mov     rf, $2222
            call    zstack_push
            lbdf    zd_fail6
            mov     rf, $3333
            call    zstack_push
            lbdf    zd_fail6
            mov     rf, $4444
            call    zstack_push
            lbdf    zd_fail6
            mov     rf, $5555
            call    zstack_push
            lbnf    zd_fail6
            mov     rb, zd_results+6
            ldi     0
            lbr     zd_store6
zd_fail6:   mov     rb, zd_results+6
            ldi     1
zd_store6:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zd_results
            ldi     ZDIAG_COUNT
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

            proc    _zdiag_data
zd_mem_buf:     ds      8
zd_stack_buf:   ds      8
zd_results:     ds      ZDIAG_COUNT
                public  zd_mem_buf
                public  zd_stack_buf
                public  zd_results
            endp
