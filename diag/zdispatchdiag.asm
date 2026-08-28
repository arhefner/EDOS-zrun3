;
; zdispatchdiag.asm - self-contained diagnostic dispatch for the V3
; opcode execution engine (zdispatch.asm)
;
; check 0 reuses the exact byte sequence from tests/test_host.c's
; "Dispatch A" scenario: a routine that doubles its one argument via
; "add" and returns the result, called with argument 5, storing the
; result in a global -- exercises call (including the routine-header/
; argument-default mechanics and the return-address/store-variable
; frame fields), variable-operand resolution against a frame's own
; locals, add, and ret/return.
;
; check 1 reuses "Dispatch C": two "je" instructions, one whose
; operands match (branch taken, skipping a store) and one whose don't
; (branch not taken, falling through normally) -- exercises both
; branch outcomes through zdisp_branch.
;
; check 2 is new: sub (stores), jz against a variable operand (not
; taken, since the value is nonzero), store's own indirect variable-
; number operand, jump (an unconditional PC change from a plain signed
; operand, not branch data), and quit.
;
; check 3 is new: print, new_line, and call + print_ret together --
; exercises the platform-level zdisp_emit_string hook (this file's own
; capture-buffer implementation, not the real K_MSG-backed one in
; lib/zdispemit.asm, so this stays bare-metal testable and asserts on
; exact captured bytes) via both the decoded-text path and the
; constant-newline path, plus print_ret's own return-true/store-
; variable mechanics.
;
; Touches no ELF-DOS kernel or BIOS entry points (this file's own
; zdisp_emit_string test double included -- see check 3's own header
; comment for why the real K_MSG-backed one isn't used here).
;

#include    include/opcodes.def
#include    include/zdecode.inc

            extrn   zminit
            extrn   zstack_init
            extrn   zvar_init
            extrn   zdisp_step

            extrn   zdisp_pc
            extrn   zdisp_quit

            extrn   zdd_mem0
            extrn   zdd_stack0
            extrn   zdd_frames0
            extrn   zdd_mem1
            extrn   zdd_stack1
            extrn   zdd_frames1
            extrn   zdd_mem2
            extrn   zdd_stack2
            extrn   zdd_frames2
            extrn   zdd_mem3
            extrn   zdd_stack3
            extrn   zdd_frames3
            extrn   zdd_captured_text
            extrn   zdd_capture_cursor
            extrn   zdd_results

ZDDIAG_COUNT:   equ     4

; zddiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zdd_results[0..ZDDIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail).
            proc    zddiag_run

; ---- check 0: call + add + ret ----
            mov     rd, zdd_mem0
            mov     rf, 64
            call    zminit
            mov     rd, zdd_stack0
            mov     rf, zdd_stack0+16
            call    zstack_init
            mov     rd, 0
            mov     rf, zdd_frames0
            mov     rc, zdd_frames0+72      ; room for 2 frames
            call    zvar_init

            mov     rf, zdd_mem0
            add16   rf, $10
            ldi     1                       ; routine: 1 local
            str     rf
            inc     rf
            ldi     0                       ; local's default: 0
            str     rf
            inc     rf
            ldi     0
            str     rf
            inc     rf
            ldi     $74                     ; add L01,L01 -> (stack)
            str     rf
            inc     rf
            ldi     1
            str     rf
            inc     rf
            ldi     1
            str     rf
            inc     rf
            ldi     0
            str     rf
            inc     rf
            ldi     $ab                     ; ret (stack)
            str     rf
            inc     rf
            ldi     0
            str     rf

            mov     rf, zdd_mem0
            add16   rf, $20
            ldi     $e0                     ; call routine($08), 5
            str     rf                      ; -> global 16 ($10)
            inc     rf
            ldi     $5f
            str     rf
            inc     rf
            ldi     $08
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $ba                     ; quit
            str     rf

            mov     rf, zdisp_pc
            ldi     0
            str     rf
            inc     rf
            ldi     $20
            str     rf
            mov     rf, zdisp_quit
            ldi     0
            str     rf

            call    zdisp_step
            lbdf    zv_fail0
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail0
            ldn     rf
            xri     $13
            lbnz    zv_fail0

            call    zdisp_step
            lbdf    zv_fail0
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail0
            ldn     rf
            xri     $17
            lbnz    zv_fail0

            call    zdisp_step
            lbdf    zv_fail0
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail0
            ldn     rf
            xri     $25
            lbnz    zv_fail0

            mov     rf, zdd_mem0            ; global 16 (address 0) == 10
            ldn     rf
            lbnz    zv_fail0
            mov     rf, zdd_mem0+1
            ldn     rf
            xri     10
            lbnz    zv_fail0

            call    zdisp_step
            lbdf    zv_fail0
            mov     rf, zdisp_quit
            ldn     rf
            lbz     zv_fail0

            mov     rb, zdd_results+0
            ldi     0
            lbr     zv_store0
zv_fail0:   mov     rb, zdd_results+0
            ldi     1
zv_store0:  str     rb

; ---- check 1: je taken and not taken ----
            mov     rd, zdd_mem1
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack1
            mov     rf, zdd_stack1+16
            call    zstack_init
            mov     rd, 0
            mov     rf, zdd_frames1
            mov     rc, zdd_frames1+36
            call    zvar_init

            mov     rf, zdd_mem1
            add16   rf, $90
            ldi     $01                     ; je 5,5 ?+5
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d                     ; store global16,99 (skipped)
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     99
            str     rf
            inc     rf
            ldi     $0d                     ; store global17,1 (landed)
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     1
            str     rf
            inc     rf
            ldi     $01                     ; je 5,6 ?+5 (not taken)
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     6
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d                     ; store global18,1
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     1
            str     rf
            inc     rf
            ldi     $ba                     ; quit
            str     rf

            mov     rf, zdisp_pc
            ldi     0
            str     rf
            inc     rf
            ldi     $90
            str     rf
            mov     rf, zdisp_quit
            ldi     0
            str     rf

            call    zdisp_step
            lbdf    zv_fail1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail1
            ldn     rf
            xri     $97
            lbnz    zv_fail1

            call    zdisp_step
            lbdf    zv_fail1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail1
            ldn     rf
            xri     $9a
            lbnz    zv_fail1

            call    zdisp_step
            lbdf    zv_fail1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail1
            ldn     rf
            xri     $9e
            lbnz    zv_fail1

            call    zdisp_step              ; store global18,1 (the
                                            ; second je's own fall-
                                            ; through instruction)
            lbdf    zv_fail1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail1
            ldn     rf
            xri     $a1
            lbnz    zv_fail1

            call    zdisp_step
            lbdf    zv_fail1
            mov     rf, zdisp_quit
            ldn     rf
            lbz     zv_fail1

            mov     rf, zdd_mem1            ; global16 == 0 (untouched)
            ldn     rf
            lbnz    zv_fail1
            mov     rf, zdd_mem1+1
            ldn     rf
            lbnz    zv_fail1
            mov     rf, zdd_mem1+2          ; global17 == 1
            ldn     rf
            lbnz    zv_fail1
            mov     rf, zdd_mem1+3
            ldn     rf
            xri     1
            lbnz    zv_fail1
            mov     rf, zdd_mem1+4          ; global18 == 1
            ldn     rf
            lbnz    zv_fail1
            mov     rf, zdd_mem1+5
            ldn     rf
            xri     1
            lbnz    zv_fail1

            mov     rb, zdd_results+1
            ldi     0
            lbr     zv_store1
zv_fail1:   mov     rb, zdd_results+1
            ldi     1
zv_store1:  str     rb

; ---- check 2: sub, jz (not taken), store, jump, quit ----
            mov     rd, zdd_mem2
            mov     rf, 64
            call    zminit
            mov     rd, zdd_stack2
            mov     rf, zdd_stack2+16
            call    zstack_init
            mov     rd, 0
            mov     rf, zdd_frames2
            mov     rc, zdd_frames2+36
            call    zvar_init

            mov     rf, zdd_mem2
            add16   rf, $20
            ldi     $15                     ; sub 100,58 -> global16
            str     rf
            inc     rf
            ldi     100
            str     rf
            inc     rf
            ldi     58
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $a0                     ; jz global16 ?+5 (var 16
            str     rf                      ; is nonzero: not taken)
            inc     rf
            ldi     16
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d                     ; store 17,7
            str     rf
            inc     rf
            ldi     17
            str     rf
            inc     rf
            ldi     7
            str     rf
            inc     rf
            ldi     $8c                     ; jump +5 (skips the next
            str     rf                      ; instruction)
            inc     rf
            ldi     0
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     $0d                     ; store 18,99 (skipped)
            str     rf
            inc     rf
            ldi     18
            str     rf
            inc     rf
            ldi     99
            str     rf
            inc     rf
            ldi     $ba                     ; quit
            str     rf

            mov     rf, zdisp_pc
            ldi     0
            str     rf
            inc     rf
            ldi     $20
            str     rf
            mov     rf, zdisp_quit
            ldi     0
            str     rf

            call    zdisp_step              ; sub
            lbdf    zv_fail2
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail2
            ldn     rf
            xri     $24
            lbnz    zv_fail2

            call    zdisp_step              ; jz (not taken)
            lbdf    zv_fail2
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail2
            ldn     rf
            xri     $27
            lbnz    zv_fail2

            call    zdisp_step              ; store 17,7
            lbdf    zv_fail2
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail2
            ldn     rf
            xri     $2a
            lbnz    zv_fail2

            call    zdisp_step              ; jump
            lbdf    zv_fail2
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail2
            ldn     rf
            xri     $30
            lbnz    zv_fail2

            call    zdisp_step              ; quit
            lbdf    zv_fail2
            mov     rf, zdisp_quit
            ldn     rf
            lbz     zv_fail2

            mov     rf, zdd_mem2            ; global16 == 42
            ldn     rf
            lbnz    zv_fail2
            mov     rf, zdd_mem2+1
            ldn     rf
            xri     42
            lbnz    zv_fail2
            mov     rf, zdd_mem2+2          ; global17 == 7
            ldn     rf
            lbnz    zv_fail2
            mov     rf, zdd_mem2+3
            ldn     rf
            xri     7
            lbnz    zv_fail2
            mov     rf, zdd_mem2+4          ; global18 == 0 (skipped)
            ldn     rf
            lbnz    zv_fail2
            mov     rf, zdd_mem2+5
            ldn     rf
            lbnz    zv_fail2

            mov     rb, zdd_results+2
            ldi     0
            lbr     zv_store2
zv_fail2:   mov     rb, zdd_results+2
            ldi     1
zv_store2:  str     rb

; ---- check 3: print, new_line, then call + print_ret ("bye", 0
; locals) -- exercises the decoded-text-to-zdisp_emit_string path
; twice (once for a plain "print", once for print_ret's own text),
; the constant newline buffer twice (print_ret's own trailing newline
; and the standalone new_line), and print_ret's return-true/store-
; variable mechanics together with call's ----
            mov     rd, zdd_mem3
            mov     rf, 64
            call    zminit
            mov     rd, zdd_stack3
            mov     rf, zdd_stack3+16
            call    zstack_init
            mov     rd, 0
            mov     rf, zdd_frames3
            mov     rc, zdd_frames3+36
            call    zvar_init

            mov     r8, zdd_captured_text
            mov     rf, zdd_capture_cursor
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf                      ; zdd_capture_cursor =
                                            ; zdd_captured_text (reset)

            mov     rf, zdd_mem3
            add16   rf, $10
            ldi     0                       ; routine: 0 locals
            str     rf
            inc     rf
            ldi     $b3                     ; print_ret "bye" ($9f$ca,
            str     rf                      ; one word, end bit set --
            inc     rf                      ; z-chars b=7,y=30,e=10)
            ldi     $9f
            str     rf
            inc     rf
            ldi     $ca
            str     rf

            mov     rf, zdd_mem3
            add16   rf, $20
            ldi     $b2                     ; print "hello" (the exact
            str     rf                      ; bytes ztext_decode's own
            inc     rf                      ; host test and zdecodediag
            ldi     $35                     ; check 3 both already
            str     rf                      ; validated)
            inc     rf
            ldi     $51
            str     rf
            inc     rf
            ldi     $c6
            str     rf
            inc     rf
            ldi     $85
            str     rf
            inc     rf
            ldi     $bb                     ; new_line
            str     rf
            inc     rf
            ldi     $e0                     ; call routine($08) ->
            str     rf                      ; global16 ($10)
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $08
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $ba                     ; quit
            str     rf

            mov     rf, zdisp_pc
            ldi     0
            str     rf
            inc     rf
            ldi     $20
            str     rf
            mov     rf, zdisp_quit
            ldi     0
            str     rf

            call    zdisp_step              ; print "hello"
            lbdf    zv_fail3
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail3
            ldn     rf
            xri     $25
            lbnz    zv_fail3

            call    zdisp_step              ; new_line
            lbdf    zv_fail3
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail3
            ldn     rf
            xri     $26
            lbnz    zv_fail3

            call    zdisp_step              ; call
            lbdf    zv_fail3
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail3
            ldn     rf
            xri     $11
            lbnz    zv_fail3

            call    zdisp_step              ; print_ret "bye" (returns)
            lbdf    zv_fail3
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail3
            ldn     rf
            xri     $2a
            lbnz    zv_fail3

            call    zdisp_step              ; quit
            lbdf    zv_fail3
            mov     rf, zdisp_quit
            ldn     rf
            lbz     zv_fail3

            mov     rf, zdd_mem3            ; global16 == 1 (print_ret's
            ldn     rf                      ; own return value)
            lbnz    zv_fail3
            mov     rf, zdd_mem3+1
            ldn     rf
            xri     1
            lbnz    zv_fail3

            mov     rf, zdd_captured_text   ; captured output ==
            ldn     rf                      ; "hello\nbye\n"
            xri     'h'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+1
            ldn     rf
            xri     'e'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+2
            ldn     rf
            xri     'l'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+3
            ldn     rf
            xri     'l'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+4
            ldn     rf
            xri     'o'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+5
            ldn     rf
            xri     10
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+6
            ldn     rf
            xri     'b'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+7
            ldn     rf
            xri     'y'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+8
            ldn     rf
            xri     'e'
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+9
            ldn     rf
            xri     10
            lbnz    zv_fail3
            mov     rf, zdd_captured_text+10
            ldn     rf
            lbnz    zv_fail3                ; NUL terminator

            mov     rb, zdd_results+3
            ldi     0
            lbr     zv_store3
zv_fail3:   mov     rb, zdd_results+3
            ldi     1
zv_store3:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zdd_results
            ldi     ZDDIAG_COUNT
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

; zdisp_emit_string (test double, replacing lib/zdispemit.asm's real
; K_MSG-backed one for this bare-metal-testable build): RF = NUL-
; terminated string. Appends it to zdd_captured_text, advancing
; zdd_capture_cursor past the copied bytes so successive calls
; concatenate (print_ret calls this twice per invocation -- once for
; its own text, once for the trailing newline -- and check 3 also
; calls a plain print/new_line before that), rather than going to any
; real console.
            proc    zdisp_emit_string
            mov     r8, zdd_capture_cursor
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = capture cursor
zdet_copy:
            ldn     rf
            lbz     zdet_copy_done
            str     r9
            inc     r9
            inc     rf
            lbr     zdet_copy
zdet_copy_done:
            ldn     rf                  ; d = 0 (the nul)
            str     r9                  ; nul-terminate the capture

            mov     r8, zdd_capture_cursor
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zdd_capture_cursor = r9
                                        ; (left pointing AT the nul,
                                        ; so the next call appends
                                        ; rather than overwrites)
            clc
            rtn
            endp

            proc    _zdispatchdiag_data
zdd_mem0:       ds      64
zdd_stack0:     ds      16
zdd_frames0:    ds      72                  ; 2 frames * 36 bytes
zdd_mem1:       ds      256
zdd_stack1:     ds      16
zdd_frames1:    ds      36                  ; 1 frame * 36 bytes
zdd_mem2:       ds      64
zdd_stack2:     ds      16
zdd_frames2:    ds      36                  ; 1 frame * 36 bytes
zdd_mem3:       ds      64
zdd_stack3:     ds      16
zdd_frames3:    ds      36                  ; 1 frame * 36 bytes
zdd_captured_text: ds   64
zdd_capture_cursor: dw  0
zdd_results:    ds      ZDDIAG_COUNT
                public  zdd_mem0
                public  zdd_stack0
                public  zdd_frames0
                public  zdd_mem1
                public  zdd_stack1
                public  zdd_frames1
                public  zdd_mem2
                public  zdd_stack2
                public  zdd_frames2
                public  zdd_mem3
                public  zdd_stack3
                public  zdd_frames3
                public  zdd_captured_text
                public  zdd_capture_cursor
                public  zdd_results
            endp
