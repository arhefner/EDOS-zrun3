;
; zvardiag.asm - self-contained diagnostic dispatch for the call-frame
; stack and variable access primitives (zvar.asm)
;
; Exercises globals (through zmem), locals (through a pushed frame),
; the eval-stack operand access (variable 0), indirect peek/replace,
; frame pop's return_pc/store_variable/stack-truncation behavior, and
; the documented error paths (no active frame, a local number beyond
; the frame's own local_count, more than 15 locals, popping an empty
; frame stack). Touches no ELF-DOS kernel or BIOS entry points.
;

#include    include/opcodes.def

            extrn   zminit
            extrn   zstack_init
            extrn   zvar_init
            extrn   zvar_frame_push
            extrn   zvar_frame_pop
            extrn   zvar_read
            extrn   zvar_write
            extrn   zvar_read_indirect
            extrn   zvar_write_indirect

            extrn   zvd_mem
            extrn   zvd_stack
            extrn   zvd_frames
            extrn   zvd_locals
            extrn   zvd_results

ZVDIAG_COUNT:   equ     9

; zvdiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zvd_results[0..ZVDIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail), in the order described below.
            proc    zvdiag_run
            mov     rd, zvd_mem
            mov     rf, 64
            call    zminit              ; guest dynamic memory for
                                        ; globals: addresses 0..63

            mov     rd, zvd_stack
            mov     rf, zvd_stack+16
            call    zstack_init         ; eval stack: 8 words capacity
                                        ; -- variable 0 (checks 4-6)
                                        ; goes through this, and
                                        ; zsptr/zstop default to 0
                                        ; (i.e. an empty, zero-capacity
                                        ; stack) without this call, so
                                        ; every push would be rejected
                                        ; as "out of bounds"

            mov     rd, 0               ; globals_base = guest addr 0
            mov     rf, zvd_frames
            mov     rc, zvd_frames+108
            call    zvar_init           ; room for 3 frames

; check 0: a global written through variable 16 reads back the same
; way, and lands in story memory at globals_base + 0
            mov     rf, $1234
            ldi     16                  ; d must be set LAST -- mov's
                                        ; own ldi's would otherwise
                                        ; clobber it before the call
            call    zvar_write
            lbdf    zv_fail0
            ldi     16
            call    zvar_read
            lbdf    zv_fail0
            ghi     rf
            xri     $12
            lbnz    zv_fail0
            glo     rf
            xri     $34
            lbnz    zv_fail0
            mov     rb, zvd_results+0
            ldi     0
            lbr     zv_store0
zv_fail0:   mov     rb, zvd_results+0
            ldi     1
zv_store0:  str     rb

; check 1: a local access before any frame has been pushed is rejected
            ldi     1
            call    zvar_read
            lbnf    zv_fail1
            mov     rb, zvd_results+1
            ldi     0
            lbr     zv_store1
zv_fail1:   mov     rb, zvd_results+1
            ldi     1
zv_store1:  str     rb

; check 2: after pushing a 2-local frame, writing local 1 and reading
; it back round-trips, and local 2 (never written) still reads its
; own default
            mov     rf, zvd_locals
            ldi     $aa
            str     rf
            inc     rf
            ldi     $aa
            str     rf
            inc     rf
            ldi     $bb
            str     rf
            inc     rf
            ldi     $bb
            str     rf

            mov     rd, $50             ; return_pc
            mov     rf, zvd_locals
            ldi     3
            plo     rc                  ; store_variable = 3
            ldi     2
            phi     rc                  ; local_count = 2
            call    zvar_frame_push
            lbdf    zv_fail2

            mov     rf, $9999
            ldi     1                   ; d set last -- see check 0
            call    zvar_write
            lbdf    zv_fail2
            ldi     1
            call    zvar_read
            lbdf    zv_fail2
            ghi     rf
            xri     $99
            lbnz    zv_fail2
            glo     rf
            xri     $99
            lbnz    zv_fail2

            ldi     2
            call    zvar_read
            lbdf    zv_fail2
            ghi     rf
            xri     $bb
            lbnz    zv_fail2
            glo     rf
            xri     $bb
            lbnz    zv_fail2

            mov     rb, zvd_results+2
            ldi     0
            lbr     zv_store2
zv_fail2:   mov     rb, zvd_results+2
            ldi     1
zv_store2:  str     rb

; check 3: local 3 -- beyond this frame's local_count of 2 -- is
; rejected
            ldi     3
            call    zvar_read
            lbnf    zv_fail3
            mov     rb, zvd_results+3
            ldi     0
            lbr     zv_store3
zv_fail3:   mov     rb, zvd_results+3
            ldi     1
zv_store3:  str     rb

; check 4: variable 0 is the eval stack -- a push/pop round trip
            mov     rf, $5555
            ldi     0                   ; d set last -- see check 0
            call    zvar_write
            lbdf    zv_fail4
            ldi     0
            call    zvar_read
            lbdf    zv_fail4
            ghi     rf
            xri     $55
            lbnz    zv_fail4
            glo     rf
            xri     $55
            lbnz    zv_fail4
            mov     rb, zvd_results+4
            ldi     0
            lbr     zv_store4
zv_fail4:   mov     rb, zvd_results+4
            ldi     1
zv_store4:  str     rb

; check 5: the indirect form peeks/replaces the stack's top in place
; -- pushing 0x7777, peeking it (without popping), replacing it with
; 0x8888, then popping for real must yield 0x8888, not 0x7777
            mov     rf, $7777
            ldi     0                   ; d set last -- see check 0
            call    zvar_write
            lbdf    zv_fail5

            ldi     0
            call    zvar_read_indirect
            lbdf    zv_fail5
            ghi     rf
            xri     $77
            lbnz    zv_fail5
            glo     rf
            xri     $77
            lbnz    zv_fail5

            mov     rf, $8888
            ldi     0                   ; d set last -- see check 0
            call    zvar_write_indirect
            lbdf    zv_fail5

            ldi     0
            call    zvar_read
            lbdf    zv_fail5
            ghi     rf
            xri     $88
            lbnz    zv_fail5
            glo     rf
            xri     $88
            lbnz    zv_fail5

            mov     rb, zvd_results+5
            ldi     0
            lbr     zv_store5
zv_fail5:   mov     rb, zvd_results+5
            ldi     1
zv_store5:  str     rb

; check 6: popping the frame returns its return_pc/store_variable and
; truncates the eval stack back to what it was at push time -- an
; operand pushed after the frame (and never popped by "the routine")
; must be gone once the frame is popped
            mov     rf, $1111
            ldi     0                   ; d set last -- see check 0
            call    zvar_write
            lbdf    zv_fail6

            call    zvar_frame_pop
            lbdf    zv_fail6
            ghi     rd
            lbnz    zv_fail6
            glo     rd
            xri     $50
            lbnz    zv_fail6
            glo     rf
            xri     3
            lbnz    zv_fail6

            ldi     0
            call    zvar_read
            lbnf    zv_fail6            ; stack must be empty again

            mov     rb, zvd_results+6
            ldi     0
            lbr     zv_store6
zv_fail6:   mov     rb, zvd_results+6
            ldi     1
zv_store6:  str     rb

; check 7: popping again -- no frame left -- is rejected
            call    zvar_frame_pop
            lbnf    zv_fail7
            mov     rb, zvd_results+7
            ldi     0
            lbr     zv_store7
zv_fail7:   mov     rb, zvd_results+7
            ldi     1
zv_store7:  str     rb

; check 8: pushing a frame with more than 15 locals is rejected
            mov     rd, $60
            mov     rf, zvd_locals
            ldi     0
            plo     rc
            ldi     16
            phi     rc                  ; local_count = 16
            call    zvar_frame_push
            lbnf    zv_fail8
            mov     rb, zvd_results+8
            ldi     0
            lbr     zv_store8
zv_fail8:   mov     rb, zvd_results+8
            ldi     1
zv_store8:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zvd_results
            ldi     ZVDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zv_tally:
            lda     rb
            lbz     zv_tally_next
            inc     rf
zv_tally_next:
            dec     r9
            glo     r9
            lbnz    zv_tally
            glo     rf
            lbnz    zv_fail_return
            clc
            rtn
zv_fail_return:
            stc
            rtn
            endp

            proc    _zvardiag_data
zvd_mem:        ds      64
zvd_stack:      ds      16                  ; eval stack: 8 words
zvd_frames:     ds      108                 ; 3 frames * 36 bytes
zvd_locals:     ds      4                   ; 2-word scratch array
zvd_results:    ds      ZVDIAG_COUNT
                public  zvd_mem
                public  zvd_stack
                public  zvd_frames
                public  zvd_locals
                public  zvd_results
            endp
