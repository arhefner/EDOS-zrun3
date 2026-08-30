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
; check 4 is new: attributes and object-tree queries (test_attr,
; set_attr, clear_attr, get_sibling, get_child, get_parent) -- reuses
; the exact object tree from zobjdiag/tests/test_host.c's obj_image
; (object table at guest 0).
;
; check 5 is new: properties (get_prop, get_prop_addr, get_prop_len,
; get_next_prop) plus insert_obj/remove_obj, sharing check 4's object
; tree and property tables.
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
            extrn   zobj_init
            extrn   zmbase
            extrn   zmend
            extrn   zdisp_step

            extrn   zdisp_pc
            extrn   zdisp_quit
            extrn   zv_globals_base
            extrn   zsbase
            extrn   zsptr
            extrn   zv_frame_base
            extrn   zv_frame_ptr
            extrn   zrand_state
            extrn   zsv_copy
            extrn   zdd_save_buf

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
            extrn   zdd_mem4
            extrn   zdd_stack4
            extrn   zdd_frames4
            extrn   zdd_mem5
            extrn   zdd_stack5
            extrn   zdd_frames5
            extrn   zdd_mem6
            extrn   zdd_stack6
            extrn   zdd_frames6
            extrn   zdd_mem7
            extrn   zdd_stack7
            extrn   zdd_frames7
            extrn   zdd_mem8
            extrn   zdd_stack8
            extrn   zdd_frames8
            extrn   zdd_mem9
            extrn   zdd_stack9
            extrn   zdd_frames9
            extrn   zdd_mem10
            extrn   zdd_stack10
            extrn   zdd_frames10
            extrn   zdd_mem11
            extrn   zdd_stack11
            extrn   zdd_frames11
            extrn   zdd_captured_text
            extrn   zdd_capture_cursor
            extrn   zdd_canned_input
            extrn   zdd_results

ZDDIAG_COUNT:   equ     12

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


; ---- check 4: attributes and object-tree queries (test_attr,
; set_attr, clear_attr, get_sibling, get_child, get_parent) --
; exercises zobj_test_attr's DF-to-branch propagation, zobj_set_attr/
; clear_attr, and zdisp_store_and_branch_nonzero's store+branch
; sequencing for get_child/get_sibling, plus get_parent's store-only
; path. Reuses the exact object tree from zobjdiag/tests/test_host.c's
; obj_image (object table at guest 0): obj1 child=2, obj2 parent=1
; sibling=3, obj3 parent=1. ----
; ---- check 4: setup ----
            mov     rd, zdd_mem4
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack4
            mov     rf, zdd_stack4+16
            call    zstack_init
            mov     rd, $00e0               ; globals_base -- clear of
                                            ; the object table (0-118)
                                            ; and the program bytes
            mov     rf, zdd_frames4
            mov     rc, zdd_frames4+36
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                      ; r9 = zmbase == the real
                                            ; address of guest 0, which
                                            ; is where this check's own
                                            ; object table starts
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem4
            ldi     119
            plo     r8                      ; r8.0 = zero-fill count
zc4_zero_loop:
            ldi     0
            str     rf
            inc     rf
            dec     r8
            glo     r8
            lbnz    zc4_zero_loop

; ---- check 4: object table (host-verified layout, reused
; from tests/test_host.c's own obj_image) ----
            mov     rf, zdd_mem4
            add16   rf, $0c         ; prop default[6] = 0x2222
            ldi     $22
            str     rf
            inc     rf
            ldi     $22
            str     rf

; obj1/obj2/obj3's own proptable_addr entry fields hold REAL/host
; addresses, not guest-relative offsets -- zobj_prop_table_addr
; returns the entry's stored field value as-is, with no translation
; (matching diag/zpropdiag.asm's own test table, which stores
; `dw zp_table+100` rather than a raw offset), so each is computed at
; runtime from zdd_mem4 here rather than written as a literal offset.
            mov     r9, zdd_mem4
            add16   r9, $64         ; r9 = real addr of obj1's proptable
                                    ; (guest offset 100)
            mov     rf, zdd_mem4
            add16   rf, $44         ; obj1: child=2, proptable (real)
            ldi     $02
            str     rf
            inc     rf
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem4
            add16   rf, $4b         ; obj2: parent=1, sibling=3
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf

            mov     r9, zdd_mem4
            add16   r9, $6e         ; r9 = real addr of obj2's proptable
                                    ; (guest offset 110)
            mov     rf, zdd_mem4
            add16   rf, $4e         ; obj2: proptable (real)
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem4
            add16   rf, $54         ; obj3: parent=1
            ldi     $01
            str     rf

            mov     r9, zdd_mem4
            add16   r9, $73         ; r9 = real addr of obj3's proptable
                                    ; (guest offset 115)
            mov     rf, zdd_mem4
            add16   rf, $57         ; obj3: proptable (real)
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem4
            add16   rf, $64         ; obj1 proptable: 1-word name, prop5(len1)=0x99, prop3(len2)=0x1234, end
            ldi     $01
            str     rf
            inc     rf
            ldi     $80
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $99
            str     rf
            inc     rf
            ldi     $23
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $34
            str     rf
            inc     rf
            ldi     $00
            str     rf

            mov     rf, zdd_mem4
            add16   rf, $6e         ; obj2 proptable: no name, end
            ldi     $00
            str     rf
            inc     rf
            ldi     $00
            str     rf

            mov     rf, zdd_mem4
            add16   rf, $73         ; obj3 proptable: no name, prop5(len1)=0x42, end
            ldi     $00
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $42
            str     rf
            inc     rf
            ldi     $00
            str     rf

; ---- check 4: program bytes ----
            mov     rf, zdd_mem4
            add16   rf, $80
            ldi     $0a
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0b
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $0c
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $92
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $91
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $14
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $93
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $15
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $0080 -- without
            ldi     0                       ; this, check4 starts from
            str     rf                      ; whatever pc check3 left
            inc     rf                      ; behind (against zdd_mem4,
            ldi     $80                     ; an entirely different
            str     rf                      ; buffer), not its own
                                            ; program's base address

; ---- check 4: steps ----
            call    zdisp_step              ; test_attr(1,3)#1 -> pc=$84
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $84
            lbnz    zv_fail4

            call    zdisp_step              ; set_attr(1,3) -> pc=$87
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $87
            lbnz    zv_fail4

            call    zdisp_step              ; test_attr(1,3)#2 -> pc=$8e
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $8e
            lbnz    zv_fail4

            call    zdisp_step              ; clear_attr(1,3) -> pc=$91
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $91
            lbnz    zv_fail4

            call    zdisp_step              ; test_attr(1,3)#3 -> pc=$95
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $95
            lbnz    zv_fail4

            call    zdisp_step              ; get_child(1) -> pc=$9c
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $9c
            lbnz    zv_fail4

            call    zdisp_step              ; get_sibling(2) -> pc=$a3
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $a3
            lbnz    zv_fail4

            call    zdisp_step              ; get_parent(2) -> pc=$a6
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $a6
            lbnz    zv_fail4

            call    zdisp_step              ; quit -> pc=$a7
            lbdf    zv_fail4
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail4
            ldn     rf
            xri     $a7
            lbnz    zv_fail4

; ---- check 4: globals ----
            ; global16 addr=$00e0
            mov     rf, zdd_mem4
            add16   rf, $00e0
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            lbnz    zv_fail4

            ; global17 addr=$00e2
            mov     rf, zdd_mem4
            add16   rf, $00e2
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            xri     $02
            lbnz    zv_fail4

            ; global18 addr=$00e4
            mov     rf, zdd_mem4
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            lbnz    zv_fail4

            ; global19 addr=$00e6
            mov     rf, zdd_mem4
            add16   rf, $00e6
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            xri     $03
            lbnz    zv_fail4

            ; global20 addr=$00e8
            mov     rf, zdd_mem4
            add16   rf, $00e8
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            lbnz    zv_fail4

            ; global21 addr=$00ea
            mov     rf, zdd_mem4
            add16   rf, $00ea
            ldn     rf
            lbnz    zv_fail4
            inc     rf
            ldn     rf
            xri     $01
            lbnz    zv_fail4

            mov     rb, zdd_results+4
            ldi     0
            lbr     zv_store4
zv_fail4:   mov     rb, zdd_results+4
            ldi     1
zv_store4:  str     rb

; ---- check 5: properties (get_prop, get_prop_addr, get_prop_len,
; get_next_prop) plus insert_obj/remove_obj -- exercises zprop_get's
; always-DF=0 path, zprop_get_addr's real->guest RF translation via
; zmbase, zprop_get_len's guest->real operand translation, and
; zprop_get_next's DF-as-instruction-error propagation, together with
; zobj_insert/zobj_remove's tree-mutation effects on a subsequent
; get_child/get_parent. Reuses the same object tree and property
; tables as check 4 (object1 has prop5(len1)=0x99 then prop3(len2)=
; 0x1234, descending order). ----
; ---- check 5: setup ----
            mov     rd, zdd_mem5
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack5
            mov     rf, zdd_stack5+16
            call    zstack_init
            mov     rd, $00e0               ; globals_base -- clear of
                                            ; the object table (0-118)
                                            ; and the program bytes
            mov     rf, zdd_frames5
            mov     rc, zdd_frames5+36
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                      ; r9 = zmbase == the real
                                            ; address of guest 0, which
                                            ; is where this check's own
                                            ; object table starts
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem5
            ldi     119
            plo     r8                      ; r8.0 = zero-fill count
zc5_zero_loop:
            ldi     0
            str     rf
            inc     rf
            dec     r8
            glo     r8
            lbnz    zc5_zero_loop

; ---- check 5: object table (host-verified layout, reused
; from tests/test_host.c's own obj_image) ----
            mov     rf, zdd_mem5
            add16   rf, $0c         ; prop default[6] = 0x2222
            ldi     $22
            str     rf
            inc     rf
            ldi     $22
            str     rf

; see check 4's own note: proptable_addr fields hold REAL/host
; addresses (zobj_prop_table_addr returns the stored field value
; as-is, no translation), computed at runtime from zdd_mem5 here.
            mov     r9, zdd_mem5
            add16   r9, $64         ; r9 = real addr of obj1's proptable
                                    ; (guest offset 100)
            mov     rf, zdd_mem5
            add16   rf, $44         ; obj1: child=2, proptable (real)
            ldi     $02
            str     rf
            inc     rf
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem5
            add16   rf, $4b         ; obj2: parent=1, sibling=3
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf

            mov     r9, zdd_mem5
            add16   r9, $6e         ; r9 = real addr of obj2's proptable
                                    ; (guest offset 110)
            mov     rf, zdd_mem5
            add16   rf, $4e         ; obj2: proptable (real)
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem5
            add16   rf, $54         ; obj3: parent=1
            ldi     $01
            str     rf

            mov     r9, zdd_mem5
            add16   r9, $73         ; r9 = real addr of obj3's proptable
                                    ; (guest offset 115)
            mov     rf, zdd_mem5
            add16   rf, $57         ; obj3: proptable (real)
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem5
            add16   rf, $64         ; obj1 proptable: 1-word name, prop5(len1)=0x99, prop3(len2)=0x1234, end
            ldi     $01
            str     rf
            inc     rf
            ldi     $80
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $99
            str     rf
            inc     rf
            ldi     $23
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $34
            str     rf
            inc     rf
            ldi     $00
            str     rf

            mov     rf, zdd_mem5
            add16   rf, $6e         ; obj2 proptable: no name, end
            ldi     $00
            str     rf
            inc     rf
            ldi     $00
            str     rf

            mov     rf, zdd_mem5
            add16   rf, $73         ; obj3 proptable: no name, prop5(len1)=0x42, end
            ldi     $00
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $42
            str     rf
            inc     rf
            ldi     $00
            str     rf

; ---- check 5: program bytes ----
            mov     rf, zdd_mem5
            add16   rf, $b0
            ldi     $11
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $a4
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $14
            str     rf
            inc     rf
            ldi     $0e
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $92
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $15
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $16
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $99
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $93
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $17
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $00b0 (see check4's
            ldi     0                       ; own note on why this
            str     rf                      ; write is required)
            inc     rf
            ldi     $b0
            str     rf

; ---- check 5: steps ----
            call    zdisp_step              ; get_prop(1,5) -> pc=$b4
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $b4
            lbnz    zv_fail5

            call    zdisp_step              ; get_prop_addr(1,5) -> pc=$b8
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $b8
            lbnz    zv_fail5

            call    zdisp_step              ; get_prop_len(var17) -> pc=$bb
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $bb
            lbnz    zv_fail5

            call    zdisp_step              ; get_next_prop(1,0) -> pc=$bf
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $bf
            lbnz    zv_fail5

            call    zdisp_step              ; get_next_prop(1,5) -> pc=$c3
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $c3
            lbnz    zv_fail5

            call    zdisp_step              ; insert_obj(3,2) -> pc=$c6
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $c6
            lbnz    zv_fail5

            call    zdisp_step              ; get_child(2) -> pc=$cd
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $cd
            lbnz    zv_fail5

            call    zdisp_step              ; remove_obj(3) -> pc=$cf
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $cf
            lbnz    zv_fail5

            call    zdisp_step              ; get_parent(3) -> pc=$d2
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $d2
            lbnz    zv_fail5

            call    zdisp_step              ; quit -> pc=$d3
            lbdf    zv_fail5
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail5
            ldn     rf
            xri     $d3
            lbnz    zv_fail5

; ---- check 5: globals ----
            ; global16 addr=$00e0
            mov     rf, zdd_mem5
            add16   rf, $00e0
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $99
            lbnz    zv_fail5

            ; global17 addr=$00e2
            mov     rf, zdd_mem5
            add16   rf, $00e2
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $68
            lbnz    zv_fail5

            ; global18 addr=$00e4
            mov     rf, zdd_mem5
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $01
            lbnz    zv_fail5

            ; global19 addr=$00e6
            mov     rf, zdd_mem5
            add16   rf, $00e6
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $05
            lbnz    zv_fail5

            ; global20 addr=$00e8
            mov     rf, zdd_mem5
            add16   rf, $00e8
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $03
            lbnz    zv_fail5

            ; global21 addr=$00ea
            mov     rf, zdd_mem5
            add16   rf, $00ea
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            xri     $03
            lbnz    zv_fail5

            ; global23 addr=$00ee
            mov     rf, zdd_mem5
            add16   rf, $00ee
            ldn     rf
            lbnz    zv_fail5
            inc     rf
            ldn     rf
            lbnz    zv_fail5

            mov     rb, zdd_results+5
            ldi     0
            lbr     zv_store5
zv_fail5:   mov     rb, zdd_results+5
            ldi     1
zv_store5:  str     rb

; ---- check 6: arithmetic and comparison opcodes (jl, jg, dec_chk,
; inc_chk, jin, test, or, and, inc, dec, load, not) -- exercises
; zdisp_slt's shared signed-16-bit-comparison helper (jl/jg directly,
; dec_chk/inc_chk's own post-adjustment branch), zvar_read_indirect/
; write_indirect's variable-NUMBER-operand handling (inc/dec/load/
; dec_chk/inc_chk), and the bitwise or/and/not/test opcodes. Reuses a
; minimal 2-object table (object2.parent=1) for jin. ----
; ---- check 6: setup ----
            mov     rd, zdd_mem6
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack6
            mov     rf, zdd_stack6+16
            call    zstack_init
            mov     rd, $00e0
            mov     rf, zdd_frames6
            mov     rc, zdd_frames6+36
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem6
            mov     r8, 256
zc6_zero_loop:
            ldi     0
            str     rf
            inc     rf
            sub16   r8, 1
            glo     r8
            lbnz    zc6_zero_loop
            ghi     r8
            lbnz    zc6_zero_loop

; ---- check 6: object table (object2.parent=1, object1 all-zero) ----
            mov     rf, zdd_mem6
            add16   rf, $4b         ; obj2 entry offset71: parent field at +4 = 75
            ldi     $01
            str     rf

; ---- check 6: program bytes ----
            mov     rf, zdd_mem6
            add16   rf, $80
            ldi     $0d
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $08
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $09
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $9f
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $95
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $96
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $96
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $9e
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $14
            str     rf
            inc     rf
            ldi     $04
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $0f
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $15
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $9e
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $16
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $14
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $17
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $9e
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $18
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $19
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $1a
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $06
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $1b
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $07
            str     rf
            inc     rf
            ldi     $0e
            str     rf
            inc     rf
            ldi     $06
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $1c
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $1d
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $0080 (see check4's
            ldi     0                       ; own note on why this
            str     rf                      ; write is required)
            inc     rf
            ldi     $80
            str     rf

; ---- check 6: steps ----
            call    zdisp_step              ; store(16,10) -> pc=$83
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $83
            lbnz    zv_fail6

            call    zdisp_step              ; or(5,3)->g17[7] -> pc=$87
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $87
            lbnz    zv_fail6

            call    zdisp_step              ; and(5,3)->g18[1] -> pc=$8b
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $8b
            lbnz    zv_fail6

            call    zdisp_step              ; not(0)->g19[FFFF] -> pc=$8e
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $8e
            lbnz    zv_fail6

            call    zdisp_step              ; inc(16) -> pc=$90
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $90
            lbnz    zv_fail6

            call    zdisp_step              ; dec(16) -> pc=$92
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $92
            lbnz    zv_fail6

            call    zdisp_step              ; dec(16)#2 -> pc=$94
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $94
            lbnz    zv_fail6

            call    zdisp_step              ; load(16)->g20[9] -> pc=$97
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $97
            lbnz    zv_fail6

            call    zdisp_step              ; dec_chk(16,15)[taken] -> pc=$9e
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $9e
            lbnz    zv_fail6

            call    zdisp_step              ; load(16)->g22[8] -> pc=$a1
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $a1
            lbnz    zv_fail6

            call    zdisp_step              ; inc_chk(16,20)[not taken] -> pc=$a5
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $a5
            lbnz    zv_fail6

            call    zdisp_step              ; store(23,1)[land] -> pc=$a8
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $a8
            lbnz    zv_fail6

            call    zdisp_step              ; load(16)->g24[9] -> pc=$ab
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $ab
            lbnz    zv_fail6

            call    zdisp_step              ; jl(3,5)[taken] -> pc=$b2
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $b2
            lbnz    zv_fail6

            call    zdisp_step              ; jg(5,3)[taken] -> pc=$b9
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $b9
            lbnz    zv_fail6

            call    zdisp_step              ; jin(2,1)[taken] -> pc=$c0
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $c0
            lbnz    zv_fail6

            call    zdisp_step              ; test(0xE,0x6)[taken] -> pc=$c7
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $c7
            lbnz    zv_fail6

            call    zdisp_step              ; jl(5,3)[not taken] -> pc=$cb
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $cb
            lbnz    zv_fail6

            call    zdisp_step              ; store(29,1)[land] -> pc=$ce
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $ce
            lbnz    zv_fail6

            call    zdisp_step              ; quit -> pc=$cf
            lbdf    zv_fail6
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail6
            ldn     rf
            xri     $cf
            lbnz    zv_fail6

; ---- check 6: globals ----
            ; global17 addr=$00e2 (or)
            mov     rf, zdd_mem6
            add16   rf, $00e2
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $07
            lbnz    zv_fail6

            ; global18 addr=$00e4 (and)
            mov     rf, zdd_mem6
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $01
            lbnz    zv_fail6

            ; global19 addr=$00e6 (not)
            mov     rf, zdd_mem6
            add16   rf, $00e6
            ldn     rf
            xri     $ff
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $ff
            lbnz    zv_fail6

            ; global20 addr=$00e8 (load after inc/dec)
            mov     rf, zdd_mem6
            add16   rf, $00e8
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $09
            lbnz    zv_fail6

            ; global21 addr=$00ea (poison(skipped))
            mov     rf, zdd_mem6
            add16   rf, $00ea
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            lbnz    zv_fail6

            ; global22 addr=$00ec (load after dec_chk)
            mov     rf, zdd_mem6
            add16   rf, $00ec
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $08
            lbnz    zv_fail6

            ; global23 addr=$00ee (inc_chk not-taken landed)
            mov     rf, zdd_mem6
            add16   rf, $00ee
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $01
            lbnz    zv_fail6

            ; global24 addr=$00f0 (load after inc_chk)
            mov     rf, zdd_mem6
            add16   rf, $00f0
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $09
            lbnz    zv_fail6

            ; global25 addr=$00f2 (poison(skipped))
            mov     rf, zdd_mem6
            add16   rf, $00f2
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            lbnz    zv_fail6

            ; global26 addr=$00f4 (poison(skipped))
            mov     rf, zdd_mem6
            add16   rf, $00f4
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            lbnz    zv_fail6

            ; global27 addr=$00f6 (poison(skipped))
            mov     rf, zdd_mem6
            add16   rf, $00f6
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            lbnz    zv_fail6

            ; global28 addr=$00f8 (poison(skipped))
            mov     rf, zdd_mem6
            add16   rf, $00f8
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            lbnz    zv_fail6

            ; global29 addr=$00fa (jl not-taken landed)
            mov     rf, zdd_mem6
            add16   rf, $00fa
            ldn     rf
            lbnz    zv_fail6
            inc     rf
            ldn     rf
            xri     $01
            lbnz    zv_fail6
            mov     rb, zdd_results+6
            ldi     0
            lbr     zv_store6
zv_fail6:   mov     rb, zdd_results+6
            ldi     1
zv_store6:  str     rb

; ---- check 7: memory access and put_prop (storew, storeb, loadw,
; loadb, put_prop) -- exercises zmwrite16/zmwrite's guest-address
; array arithmetic and the new zprop_put primitive (single-byte write
; for a length-1 property, big-endian word write for length-2, DF=1
; for a property the object doesn't have). Reuses a minimal 1-object
; table (object1, proptable @ guest $60: prop5 len1, prop3 len2). ----
; ---- check 7: setup ----
            mov     rd, zdd_mem7
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack7
            mov     rf, zdd_stack7+16
            call    zstack_init
            mov     rd, $00e0
            mov     rf, zdd_frames7
            mov     rc, zdd_frames7+36
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem7
            mov     r8, 256
zc7_zero_loop:
            ldi     0
            str     rf
            inc     rf
            sub16   r8, 1
            glo     r8
            lbnz    zc7_zero_loop
            ghi     r8
            lbnz    zc7_zero_loop

; ---- check 7: object table (object1 has prop5 len1=0x11, prop3 len2=0x2233, proptable @ guest $60) ----
            mov     r9, zdd_mem7
            add16   r9, $60         ; r9 = real addr of obj1's proptable
            mov     rf, zdd_mem7
            add16   rf, $44         ; obj1 entry offset68: child=0(unused), proptable (real) at +1,+2
            ldi     $00
            str     rf
            inc     rf
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem7
            add16   rf, $60         ; obj1 proptable: no name, prop5(len1)=0x11, prop3(len2)=0x2233, end
            ldi     $00
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $23
            str     rf
            inc     rf
            ldi     $22
            str     rf
            inc     rf
            ldi     $33
            str     rf
            inc     rf
            ldi     $00
            str     rf

; ---- check 7: program bytes ----
            mov     rf, zdd_mem7
            add16   rf, $80
            ldi     $e1
            str     rf
            inc     rf
            ldi     $53
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $34
            str     rf
            inc     rf
            ldi     $e1
            str     rf
            inc     rf
            ldi     $53
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $56
            str     rf
            inc     rf
            ldi     $78
            str     rf
            inc     rf
            ldi     $0f
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $0f
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $e2
            str     rf
            inc     rf
            ldi     $57
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $04
            str     rf
            inc     rf
            ldi     $99
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $04
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $e2
            str     rf
            inc     rf
            ldi     $57
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $ab
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $e3
            str     rf
            inc     rf
            ldi     $57
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $77
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $14
            str     rf
            inc     rf
            ldi     $e3
            str     rf
            inc     rf
            ldi     $53
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $34
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $15
            str     rf
            inc     rf
            ldi     $e3
            str     rf
            inc     rf
            ldi     $57
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $09
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $0080
            ldi     0
            str     rf
            inc     rf
            ldi     $80
            str     rf

; ---- check 7: steps ----
            call    zdisp_step              ; storew($10,0,0x1234) -> pc=$86
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $86
            lbnz    zv_fail7

            call    zdisp_step              ; storew($10,1,0x5678) -> pc=$8c
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $8c
            lbnz    zv_fail7

            call    zdisp_step              ; loadw($10,0)->g16[1234] -> pc=$90
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $90
            lbnz    zv_fail7

            call    zdisp_step              ; loadw($10,1)->g17[5678] -> pc=$94
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $94
            lbnz    zv_fail7

            call    zdisp_step              ; storeb($10,4,0x99) -> pc=$99
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $99
            lbnz    zv_fail7

            call    zdisp_step              ; loadb($10,4)->g18[0099] -> pc=$9d
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $9d
            lbnz    zv_fail7

            call    zdisp_step              ; storeb($10,5,0xAB) -> pc=$a2
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $a2
            lbnz    zv_fail7

            call    zdisp_step              ; loadb($10,5)->g19[00AB] -> pc=$a6
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $a6
            lbnz    zv_fail7

            call    zdisp_step              ; put_prop(1,5,0x77) -> pc=$ab
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $ab
            lbnz    zv_fail7

            call    zdisp_step              ; get_prop(1,5)->g20[0077] -> pc=$af
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $af
            lbnz    zv_fail7

            call    zdisp_step              ; put_prop(1,3,0x1234) -> pc=$b5
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $b5
            lbnz    zv_fail7

            call    zdisp_step              ; get_prop(1,3)->g21[1234] -> pc=$b9
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $b9
            lbnz    zv_fail7

            call    zdisp_step              ; put_prop(1,9,99)[expect DF=1]
            lbnf    zv_fail7                ; expect DF=1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $be
            lbnz    zv_fail7

            call    zdisp_step              ; quit -> pc=$bf
            lbdf    zv_fail7
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail7
            ldn     rf
            xri     $bf
            lbnz    zv_fail7

; ---- check 7: globals ----
            ; global16 addr=$00e0 (loadw index0)
            mov     rf, zdd_mem7
            add16   rf, $00e0
            ldn     rf
            xri     $12
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $34
            lbnz    zv_fail7

            ; global17 addr=$00e2 (loadw index1)
            mov     rf, zdd_mem7
            add16   rf, $00e2
            ldn     rf
            xri     $56
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $78
            lbnz    zv_fail7

            ; global18 addr=$00e4 (loadb index4)
            mov     rf, zdd_mem7
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $99
            lbnz    zv_fail7

            ; global19 addr=$00e6 (loadb index5)
            mov     rf, zdd_mem7
            add16   rf, $00e6
            ldn     rf
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $ab
            lbnz    zv_fail7

            ; global20 addr=$00e8 (get_prop after put_prop len1)
            mov     rf, zdd_mem7
            add16   rf, $00e8
            ldn     rf
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $77
            lbnz    zv_fail7

            ; global21 addr=$00ea (get_prop after put_prop len2)
            mov     rf, zdd_mem7
            add16   rf, $00ea
            ldn     rf
            xri     $12
            lbnz    zv_fail7
            inc     rf
            ldn     rf
            xri     $34
            lbnz    zv_fail7
            mov     rb, zdd_results+7
            ldi     0
            lbr     zv_store7
zv_fail7:   mov     rb, zdd_results+7
            ldi     1
zv_store7:  str     rb

; ---- check 8: print family (print_char, print_num, print_addr,
; print_paddr, print_obj) and stack opcodes (push, pull, pop,
; ret_popped, via a call) -- exercises zdisp_print_at's own generous-
; length self-terminating decode (print_addr/print_paddr), zobj_
; short_name's exact-length decode (print_obj), ym_fmt_uint32's
; signed-negation wrapper (print_num), and the eval-stack push/pop/
; pull-indirect-write mechanics through a real call/return. Reuses a
; minimal 1-object table (object1, short name "hello") plus a
; floating z-text blob (also "hello") for print_addr/print_paddr. ----
; ---- check 8: setup ----
            mov     rd, zdd_mem8
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack8
            mov     rf, zdd_stack8+16
            call    zstack_init
            mov     rd, $00e0
            mov     rf, zdd_frames8
            mov     rc, zdd_frames8+72      ; room for 2 frames (the
                                            ; routine call below nests
                                            ; one)
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem8
            mov     r8, 256
zc8_zero_loop:
            ldi     0
            str     rf
            inc     rf
            sub16   r8, 1
            glo     r8
            lbnz    zc8_zero_loop
            ghi     r8
            lbnz    zc8_zero_loop

            mov     r8, zdd_captured_text
            mov     rf, zdd_capture_cursor
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf                      ; zdd_capture_cursor =
                                            ; zdd_captured_text (reset)

; ---- check 8: object table (object1 short name = "hello", proptable @ guest $50, no properties) ----
            mov     r9, zdd_mem8
            add16   r9, $50         ; r9 = real addr of obj1's proptable
            mov     rf, zdd_mem8
            add16   rf, $44         ; obj1 entry offset68: child=0(unused), proptable (real) at +1,+2
            ldi     $00
            str     rf
            inc     rf
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdd_mem8
            add16   rf, $50         ; obj1 proptable: short name "hello" (2 words), no properties
            ldi     $02
            str     rf
            inc     rf
            ldi     $35
            str     rf
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
            ldi     $00
            str     rf

            mov     rf, zdd_mem8
            add16   rf, $70         ; floating z-text blob "hello", for
                                    ; print_addr($70)/print_paddr($38)
            ldi     $35
            str     rf
            inc     rf
            ldi     $51
            str     rf
            inc     rf
            ldi     $c6
            str     rf
            inc     rf
            ldi     $85
            str     rf

            mov     rf, zdd_mem8
            add16   rf, $10         ; routine (0 locals): push(77), ret_popped
            ldi     $00
            str     rf
            inc     rf
            ldi     $e8
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $4d
            str     rf
            inc     rf
            ldi     $b8
            str     rf

; ---- check 8: program bytes ----
            mov     rf, zdd_mem8
            add16   rf, $90
            ldi     $e5
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $41
            str     rf
            inc     rf
            ldi     $e5
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $42
            str     rf
            inc     rf
            ldi     $e6
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $04
            str     rf
            inc     rf
            ldi     $d2
            str     rf
            inc     rf
            ldi     $e6
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $ff
            str     rf
            inc     rf
            ldi     $d6
            str     rf
            inc     rf
            ldi     $e6
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $97
            str     rf
            inc     rf
            ldi     $70
            str     rf
            inc     rf
            ldi     $9d
            str     rf
            inc     rf
            ldi     $38
            str     rf
            inc     rf
            ldi     $9a
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $e8
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $e9
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $e8
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $05
            str     rf
            inc     rf
            ldi     $e8
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $b9
            str     rf
            inc     rf
            ldi     $e9
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $e0
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $08
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $0090
            ldi     0
            str     rf
            inc     rf
            ldi     $90
            str     rf

; ---- check 8: steps ----
            call    zdisp_step              ; print_char(65) -> pc=$93
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $93
            lbnz    zv_fail8

            call    zdisp_step              ; print_char(66) -> pc=$96
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $96
            lbnz    zv_fail8

            call    zdisp_step              ; print_num(1234) -> pc=$9a
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $9a
            lbnz    zv_fail8

            call    zdisp_step              ; print_num(-42) -> pc=$9e
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $9e
            lbnz    zv_fail8

            call    zdisp_step              ; print_num(0) -> pc=$a1
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $a1
            lbnz    zv_fail8

            call    zdisp_step              ; print_addr($70) -> pc=$a3
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $a3
            lbnz    zv_fail8

            call    zdisp_step              ; print_paddr($38) -> pc=$a5
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $a5
            lbnz    zv_fail8

            call    zdisp_step              ; print_obj(1) -> pc=$a7
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $a7
            lbnz    zv_fail8

            call    zdisp_step              ; push(99) -> pc=$aa
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $aa
            lbnz    zv_fail8

            call    zdisp_step              ; pull(g16) -> pc=$ad
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $ad
            lbnz    zv_fail8

            call    zdisp_step              ; push(5) -> pc=$b0
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $b0
            lbnz    zv_fail8

            call    zdisp_step              ; push(10) -> pc=$b3
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $b3
            lbnz    zv_fail8

            call    zdisp_step              ; pop -> pc=$b4
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $b4
            lbnz    zv_fail8

            call    zdisp_step              ; pull(g17) -> pc=$b7
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $b7
            lbnz    zv_fail8

            call    zdisp_step              ; call routine($08)->g18 -> pc=$11
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $11
            lbnz    zv_fail8

            call    zdisp_step              ; push(77) [in routine] -> pc=$14
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $14
            lbnz    zv_fail8

            call    zdisp_step              ; ret_popped [in routine] -> pc=$bb (return addr)
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $bb
            lbnz    zv_fail8

            call    zdisp_step              ; quit -> pc=$bc
            lbdf    zv_fail8
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail8
            ldn     rf
            xri     $bc
            lbnz    zv_fail8

; ---- check 8: globals ----
            ; global16 addr=$00e0 (pull after push(99))
            mov     rf, zdd_mem8
            add16   rf, $00e0
            ldn     rf
            lbnz    zv_fail8
            inc     rf
            ldn     rf
            xri     $63
            lbnz    zv_fail8

            ; global17 addr=$00e2 (pull after push/push/pop)
            mov     rf, zdd_mem8
            add16   rf, $00e2
            ldn     rf
            lbnz    zv_fail8
            inc     rf
            ldn     rf
            xri     $05
            lbnz    zv_fail8

            ; global18 addr=$00e4 (call routine ret_popped(push 77))
            mov     rf, zdd_mem8
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail8
            inc     rf
            ldn     rf
            xri     $4d
            lbnz    zv_fail8

; ---- check 8: captured text (expect 'AB1234-420hellohellohello') ----
            mov     rf, zdd_captured_text
            ldn     rf
            xri     'A'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+1
            ldn     rf
            xri     'B'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+2
            ldn     rf
            xri     '1'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+3
            ldn     rf
            xri     '2'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+4
            ldn     rf
            xri     '3'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+5
            ldn     rf
            xri     '4'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+6
            ldn     rf
            xri     '-'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+7
            ldn     rf
            xri     '4'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+8
            ldn     rf
            xri     '2'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+9
            ldn     rf
            xri     '0'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+10
            ldn     rf
            xri     'h'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+11
            ldn     rf
            xri     'e'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+12
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+13
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+14
            ldn     rf
            xri     'o'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+15
            ldn     rf
            xri     'h'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+16
            ldn     rf
            xri     'e'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+17
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+18
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+19
            ldn     rf
            xri     'o'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+20
            ldn     rf
            xri     'h'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+21
            ldn     rf
            xri     'e'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+22
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+23
            ldn     rf
            xri     'l'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+24
            ldn     rf
            xri     'o'
            lbnz    zv_fail8

            mov     rf, zdd_captured_text+25
            ldn     rf
            lbnz    zv_fail8                ; NUL terminator
            mov     rb, zdd_results+8
            ldi     0
            lbr     zv_store8
zv_fail8:   mov     rb, zdd_results+8
            ldi     1
zv_store8:  str     rb

; ---- check 9: random and sread -- exercises zrand_step's xorshift32
; PRNG (deterministic once reseeded via random(-99), matching a Python
; simulation of the same algorithm) and zdisp_umod16's general 16-bit
; modulo, plus sread's full header-dictionary-lookup -> zdict_init ->
; zparse_init -> zparse_tokenize -> real-to-guest entry_addr
; translation pipeline. Reuses diag/zdictdiag.asm's own hardware-
; verified 3-entry dictionary ("cat"/"dog"/"run") verbatim, and a
; canned "cat dog" input via this file's own zdisp_read_line test
; double (see its own header for why the real zterm_read_line-backed
; one isn't used here). ----
; ---- check 9: setup ----
            mov     rd, zdd_mem9
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack9
            mov     rf, zdd_stack9+16
            call    zstack_init
            mov     rd, $00e0
            mov     rf, zdd_frames9
            mov     rc, zdd_frames9+36
            call    zvar_init

            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     rd, r9
            call    zobj_init

            mov     rf, zdd_mem9
            mov     r8, 256
zc9_zero_loop:
            ldi     0
            str     rf
            inc     rf
            sub16   r8, 1
            glo     r8
            lbnz    zc9_zero_loop
            ghi     r8
            lbnz    zc9_zero_loop

; ---- check 9: story header (dictionary address @ guest 8) ----
            mov     rf, zdd_mem9
            add16   rf, $08
            ldi     $00
            str     rf
            inc     rf
            ldi     $30              ; dictionary at guest $30
            str     rf

; ---- check 9: dictionary table (reused verbatim from diag/zdictdiag.asm's own hardware-verified zt_dict: "cat"/"dog"/"run") ----
            mov     rf, zdd_mem9
            add16   rf, $30
            ldi     $01
            str     rf
            inc     rf
            ldi     $2c
            str     rf
            inc     rf
            ldi     $07
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $20
            str     rf
            inc     rf
            ldi     $d9
            str     rf
            inc     rf
            ldi     $94
            str     rf
            inc     rf
            ldi     $a5
            str     rf
            inc     rf
            ldi     $aa
            str     rf
            inc     rf
            ldi     $bb
            str     rf
            inc     rf
            ldi     $cc
            str     rf
            inc     rf
            ldi     $26
            str     rf
            inc     rf
            ldi     $8c
            str     rf
            inc     rf
            ldi     $94
            str     rf
            inc     rf
            ldi     $a5
            str     rf
            inc     rf
            ldi     $dd
            str     rf
            inc     rf
            ldi     $ee
            str     rf
            inc     rf
            ldi     $ff
            str     rf
            inc     rf
            ldi     $5f
            str     rf
            inc     rf
            ldi     $53
            str     rf
            inc     rf
            ldi     $94
            str     rf
            inc     rf
            ldi     $a5
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $22
            str     rf
            inc     rf
            ldi     $33
            str     rf

; ---- check 9: text buffer (max_length=20 @ guest $60) and parse buffer (max_words=4 @ guest $80) headers ----
            mov     rf, zdd_mem9
            add16   rf, $60
            ldi     20
            str     rf

            mov     rf, zdd_mem9
            add16   rf, $80
            ldi     4
            str     rf

; ---- check 9: program bytes ----
            mov     rf, zdd_mem9
            add16   rf, $a0
            ldi     $e7
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $ff
            str     rf
            inc     rf
            ldi     $9d
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $e7
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $e7
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $0a
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $e7
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $e8
            str     rf
            inc     rf
            ldi     $13
            str     rf
            inc     rf
            ldi     $e4
            str     rf
            inc     rf
            ldi     $5f
            str     rf
            inc     rf
            ldi     $60
            str     rf
            inc     rf
            ldi     $80
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $00a0
            ldi     0
            str     rf
            inc     rf
            ldi     $a0
            str     rf

; ---- check 9: steps ----
            call    zdisp_step              ; random(-99)->g16[0] -> pc=$a5
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $a5
            lbnz    zv_fail9

            call    zdisp_step              ; random(10)->g17[6] -> pc=$a9
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $a9
            lbnz    zv_fail9

            call    zdisp_step              ; random(10)->g18[6] -> pc=$ad
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $ad
            lbnz    zv_fail9

            call    zdisp_step              ; random(1000)->g19[360] -> pc=$b2
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $b2
            lbnz    zv_fail9

            call    zdisp_step              ; sread($60,$80) -> pc=$b6
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $b6
            lbnz    zv_fail9

            call    zdisp_step              ; quit -> pc=$b7
            lbdf    zv_fail9
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail9
            ldn     rf
            xri     $b7
            lbnz    zv_fail9

; ---- check 9: globals ----
            ; global16 addr=$00e0 (random(-99) reseed)
            mov     rf, zdd_mem9
            add16   rf, $00e0
            ldn     rf
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            lbnz    zv_fail9

            ; global17 addr=$00e2 (random(10) draw 1)
            mov     rf, zdd_mem9
            add16   rf, $00e2
            ldn     rf
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     $06
            lbnz    zv_fail9

            ; global18 addr=$00e4 (random(10) draw 2)
            mov     rf, zdd_mem9
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     $06
            lbnz    zv_fail9

            ; global19 addr=$00e6 (random(1000) draw 3 [360])
            mov     rf, zdd_mem9
            add16   rf, $00e6
            ldn     rf
            xri     $01
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     $68
            lbnz    zv_fail9

; ---- check 9: parse buffer (word_count, then 4 bytes/word: entry_addr hi/lo, length, position) ----
            ; word_count == 2
            mov     rf, zdd_mem9
            add16   rf, $81
            ldn     rf
            xri     2
            lbnz    zv_fail9

            ; word[0] = "cat": entry_addr=$35 (dict $30 + offset 5), length=3, position=1
            mov     rf, zdd_mem9
            add16   rf, $82
            ldn     rf
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     $35
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     3
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     1
            lbnz    zv_fail9

            ; word[1] = "dog": entry_addr=$3c (dict $30 + offset 12), length=3, position=5
            mov     rf, zdd_mem9
            add16   rf, $86
            ldn     rf
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     $3c
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     3
            lbnz    zv_fail9
            inc     rf
            ldn     rf
            xri     5
            lbnz    zv_fail9
            mov     rb, zdd_results+9
            ldi     0
            lbr     zv_store9
zv_fail9:   mov     rb, zdd_results+9
            ldi     1
zv_store9:  str     rb

; ---- check 10: output_stream / input_stream -- exercises the
; +-3 == unsupported rule (zds_output_stream returns DF=1 for stream
; 3's memory-table redirect, which doesn't fit zdisp_emit_string's own
; batched-string interface -- see its own header) while every other
; stream number, and input_stream entirely, are accepted as a no-op,
; matching host's own "no separate transcript sink" simplification. ----
; ---- check 10: setup ----
            mov     rd, zdd_mem10
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack10
            mov     rf, zdd_stack10+16
            call    zstack_init
            mov     rd, 0
            mov     rf, zdd_frames10
            mov     rc, zdd_frames10+36
            call    zvar_init

; ---- check 10: program bytes ----
            mov     rf, zdd_mem10
            add16   rf, $80
            ldi     $f3
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $f3
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $03
            str     rf
            inc     rf
            ldi     $f3
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $ff
            str     rf
            inc     rf
            ldi     $fd
            str     rf
            inc     rf
            ldi     $f3
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $02
            str     rf
            inc     rf
            ldi     $f4
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     $ba
            str     rf

            mov     rf, zdisp_pc            ; pc = $0080
            ldi     0
            str     rf
            inc     rf
            ldi     $80
            str     rf

; ---- check 10: steps ----
            call    zdisp_step              ; output_stream(1)[expect DF=0] -> pc=$83
            lbdf    zv_fail10
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $83
            lbnz    zv_fail10

            call    zdisp_step              ; output_stream(3)[expect DF=1]
            lbnf    zv_fail10               ; expect DF=1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $86
            lbnz    zv_fail10

            call    zdisp_step              ; output_stream(-3)[expect DF=1]
            lbnf    zv_fail10               ; expect DF=1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $8a
            lbnz    zv_fail10

            call    zdisp_step              ; output_stream(2)[expect DF=0] -> pc=$8d
            lbdf    zv_fail10
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $8d
            lbnz    zv_fail10

            call    zdisp_step              ; input_stream(0)[expect DF=0] -> pc=$90
            lbdf    zv_fail10
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $90
            lbnz    zv_fail10

            call    zdisp_step              ; quit -> pc=$91
            lbdf    zv_fail10
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail10
            ldn     rf
            xri     $91
            lbnz    zv_fail10
            mov     rb, zdd_results+10
            ldi     0
            lbr     zv_store10
zv_fail10:  mov     rb, zdd_results+10
            ldi     1
zv_store10: str     rb

; ---- check 11: save / restore / restart -- exercises the V1-3
; branch-encoding save/restore semantics (save unconditionally commits
; its own branch target first, then undoes it only if the save itself
; fails; restore's own branch data is present in the encoding but
; never evaluated, since a successful restore overwrites zdisp_pc
; wholesale as part of the restored state). Only ONE restore call ever
; runs -- its own PC-jump re-enters the code right after save, but
; nothing further is stepped after that, so there's no risk of
; re-hitting the same restore instruction a second time (a Z-machine
; program genuinely cannot detect "was I just restored" from within
; its own restorable state to loop-and-skip a repeat call -- restore's
; whole point is that EVERYTHING written after the save point,
; including any such counter, reverts too; see the globals assertions
; below, which lean into this rather than fight it: only g16, written
; BEFORE save, should reflect the corrupt-then-restore round trip,
; while g18/g21 -- written only after save -- must revert to their
; untouched pre-save value). Also verifies the eval stack itself was
; genuinely restored (length and content), not just left alone.
; restart's own stub (always DF=1, no pristine-memory source exists
; anywhere in this project yet) is tested separately, via its own
; fresh mini-program and pc reset, entirely unentangled from the
; save/restore control flow above. ----
; ---- check 11: setup ----
            mov     rd, zdd_mem11
            mov     rf, 256
            call    zminit
            mov     rd, zdd_stack11
            mov     rf, zdd_stack11+16
            call    zstack_init
            mov     rd, $00e0
            mov     rf, zdd_frames11
            mov     rc, zdd_frames11+36
            call    zvar_init

            mov     rf, zdd_mem11
            mov     r8, 256
zc11_zero_loop:
            ldi     0
            str     rf
            inc     rf
            sub16   r8, 1
            glo     r8
            lbnz    zc11_zero_loop
            ghi     r8
            lbnz    zc11_zero_loop

; ---- check 11: program bytes ----
            mov     rf, zdd_mem11
            add16   rf, $80
            ldi     $e8
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $2a
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $6f
            str     rf
            inc     rf
            ldi     $b5
            str     rf
            inc     rf
            ldi     $c5
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $11
            str     rf
            inc     rf
            ldi     $63
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $12
            str     rf
            inc     rf
            ldi     $01
            str     rf
            inc     rf
            ldi     $e9
            str     rf
            inc     rf
            ldi     $7f
            str     rf
            inc     rf
            ldi     $15
            str     rf
            inc     rf
            ldi     $0d
            str     rf
            inc     rf
            ldi     $10
            str     rf
            inc     rf
            ldi     $de
            str     rf
            inc     rf
            ldi     $b6
            str     rf
            inc     rf
            ldi     $c0
            str     rf

; ---- check 11: restart mini-program ----
            mov     rf, zdd_mem11
            add16   rf, $b0
            ldi     $b7
            str     rf

            mov     rf, zdisp_pc            ; pc = $0080
            ldi     0
            str     rf
            inc     rf
            ldi     $80
            str     rf

; landing addr=$8b
; ---- check 11: steps ----
            call    zdisp_step              ; push(42) -> pc=$83
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $83
            lbnz    zv_fail11

            call    zdisp_step              ; store(16,111) -> pc=$86
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $86
            lbnz    zv_fail11

            call    zdisp_step              ; save[taken] -> pc=$8b
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $8b
            lbnz    zv_fail11

            call    zdisp_step              ; store(18,1) -> pc=$8e
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $8e
            lbnz    zv_fail11

            call    zdisp_step              ; pull(g21) -> pc=$91
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $91
            lbnz    zv_fail11

            call    zdisp_step              ; store(16,222)[corrupt] -> pc=$94
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $94
            lbnz    zv_fail11

            call    zdisp_step              ; restore -> pc=$8b
            lbdf    zv_fail11
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $8b
            lbnz    zv_fail11

; ---- check 11: eval stack restored to contain [42] ----
            mov     rf, zsbase
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = *zsbase
            mov     rf, zsptr
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = *zsptr
            mov     r8, ra
            sub16   r8, r9              ; r8 = *zsptr - *zsbase (length)
            glo     r8
            xri     2
            lbnz    zv_fail11
            ghi     r8
            lbnz    zv_fail11           ; length must be exactly 2

            mov     rf, r9
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $2a
            lbnz    zv_fail11           ; content must be 0x002A (42)

; ---- check 11: globals (all written after the save point must revert to their untouched pre-save value; only g16, written BEFORE save, should reflect the corrupt-then-restore round trip) ----
            ; global16 addr=$00e0 (g16: set before save, corrupted, restored)
            mov     rf, zdd_mem11
            add16   rf, $00e0
            ldn     rf
            lbnz    zv_fail11
            inc     rf
            ldn     rf
            xri     $6f
            lbnz    zv_fail11

            ; global18 addr=$00e4 (g18: set only after save -- reverted to untouched)
            mov     rf, zdd_mem11
            add16   rf, $00e4
            ldn     rf
            lbnz    zv_fail11
            inc     rf
            ldn     rf
            lbnz    zv_fail11

            ; global21 addr=$00ea (g21: set only after save (by pull) -- reverted)
            mov     rf, zdd_mem11
            add16   rf, $00ea
            ldn     rf
            lbnz    zv_fail11
            inc     rf
            ldn     rf
            lbnz    zv_fail11

; ---- check 11: restart (separate mini-program, fresh pc) ----
            mov     rf, zdisp_pc
            ldi     0
            str     rf
            inc     rf
            ldi     $b0
            str     rf

            call    zdisp_step              ; restart[expect DF=1]
            lbnf    zv_fail11               ; expect DF=1
            mov     rf, zdisp_pc
            lda     rf
            lbnz    zv_fail11
            ldn     rf
            xri     $b1
            lbnz    zv_fail11
            mov     rb, zdd_results+11
            ldi     0
            lbr     zv_store11
zv_fail11:  mov     rb, zdd_results+11
            ldi     1
zv_store11: str     rb
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

; zdisp_read_line (test double, replacing lib/zdispread.asm's real
; zterm_read_line-backed one for this bare-metal-testable build): RD =
; real text buffer address (byte 0 = max length, ignored here -- this
; is a controlled test scenario, not real user input). Writes a fixed
; canned string into buf+1, NUL-terminated, always DF=0 (never
; "aborted").
            proc    zdisp_read_line
            mov     r8, rd
            inc     r8                  ; r8 = buffer+1
            mov     r9, zdd_canned_input
zdrl_copy:
            ldn     r9
            lbz     zdrl_copy_done
            str     r8
            inc     r8
            inc     r9
            lbr     zdrl_copy
zdrl_copy_done:
            ldn     r9                  ; d = 0 (the nul)
            str     r8
            clc
            rtn
            endp

; zdisp_save_game / zdisp_restore_game (test double, replacing
; lib/zdispsave.asm's real K_FILE-backed pair): writes/reads the exact
; same self-describing state blob (see lib/zdispsave.asm's own header
; for the field layout) into/from zdd_save_buf instead of a real file,
; so save/restore stay bare-metal testable. Always succeeds (DF=0).
            proc    zdisp_save_game
            mov     r9, zdd_save_buf   ; r9 = write cursor

            mov     r8, zdisp_pc
            lda     r8
            str     r9
            inc     r9
            ldn     r8
            str     r9
            inc     r9                  ; pc

            mov     r8, zv_globals_base
            lda     r8
            str     r9
            inc     r9
            ldn     r8
            str     r9
            inc     r9                  ; globals_base

            mov     r8, zsptr
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = *zsptr
            mov     r8, zsbase
            lda     r8
            phi     rb
            ldn     r8
            plo     rb                  ; rb = *zsbase
            mov     r7, ra
            sub16   r7, rb              ; r7 = eval stack length

            ghi     r7
            str     r9
            inc     r9
            glo     r7
            str     r9
            inc     r9

            mov     r8, rb              ; r8 = copy source (*zsbase)
            call    zsv_copy

            mov     r8, zv_frame_ptr
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            mov     r8, zv_frame_base
            lda     r8
            phi     rb
            ldn     r8
            plo     rb
            mov     r7, ra
            sub16   r7, rb              ; r7 = frame stack length

            ghi     r7
            str     r9
            inc     r9
            glo     r7
            str     r9
            inc     r9

            mov     r8, rb
            call    zsv_copy

            mov     r8, zrand_state
            ldi     4
            plo     r7
            ldi     0
            phi     r7
            call    zsv_copy

            mov     r8, zmend
            lda     r8
            phi     r7
            ldn     r8
            plo     r7                  ; r7 = *zmend (dynamic memory
                                        ; length)
            ghi     r7
            str     r9
            inc     r9
            glo     r7
            str     r9
            inc     r9

            mov     r8, zmbase
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = *zmbase
            mov     r8, ra
            call    zsv_copy

            clc
            rtn
            endp

; zsv_copy (internal, shared by zdisp_save_game/zdisp_restore_game):
; R8 = source, R9 = destination, R7 = byte count (set immediately
; before the call). Copies R7 bytes from R8 to R9, advancing both.
; Called from within the same proc's own logic via a plain `call`, but
; also from zdisp_restore_game below -- needs extrn/public since it's
; a separate proc, same as every other same-file cross-proc helper in
; this project.
            proc    zsv_copy
zsvc_loop:
            glo     r7
            lbnz    zsvc_have
            ghi     r7
            lbz     zsvc_done
zsvc_have:
            ldn     r8
            str     r9
            inc     r8
            inc     r9
            sub16   r7, 1
            lbr     zsvc_loop
zsvc_done:
            rtn
            endp

            proc    zdisp_restore_game
            mov     r8, zdd_save_buf   ; r8 = read cursor into the
                                        ; save buffer (the SOURCE
                                        ; register zsv_copy expects)

            mov     r9, zdisp_pc
            lda     r8
            str     r9
            inc     r9
            lda     r8
            str     r9                  ; pc

            mov     r9, zv_globals_base
            lda     r8
            str     r9
            inc     r9
            lda     r8
            str     r9                  ; globals_base

            lda     r8
            phi     r7
            lda     r8
            plo     r7                  ; r7 = eval stack length

            mov     r9, zsbase
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = *zsbase (copy dest)

            mov     rb, ra
            add16   rb, r7              ; rb = *zsbase + length = the
                                        ; new zsptr -- computed BEFORE
                                        ; zsv_copy, which decrements r7
                                        ; to 0 as its own loop counter
                                        ; (rb itself survives zsv_copy,
                                        ; which only touches r7/r8/r9)

            mov     r9, ra
            call    zsv_copy            ; r8 advances past the eval
                                        ; stack content, ready for the
                                        ; frame-stack length field

            mov     r9, zsptr
            ghi     rb
            str     r9
            inc     r9
            glo     rb
            str     r9                  ; zsptr = the stashed new value

            lda     r8
            phi     r7
            lda     r8
            plo     r7                  ; r7 = frame stack length

            mov     r9, zv_frame_base
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = *zv_frame_base

            mov     rb, ra
            add16   rb, r7              ; new frame_ptr, computed
                                        ; before zsv_copy (same reason
                                        ; as the eval-stack section
                                        ; above)

            mov     r9, ra
            call    zsv_copy

            mov     r9, zv_frame_ptr
            ghi     rb
            str     r9
            inc     r9
            glo     rb
            str     r9                  ; zv_frame_ptr = the stashed
                                        ; new value

            mov     r9, zrand_state
            ldi     4
            plo     r7
            ldi     0
            phi     r7
            call    zsv_copy            ; rand_state (raw 4 bytes)

            lda     r8
            phi     r7
            lda     r8
            plo     r7                  ; r7 = dynamic memory length
                                        ; (also the new zmend)

            mov     r9, zmend
            ghi     r7
            str     r9
            inc     r9
            glo     r7
            str     r9                  ; zmend = length

            mov     r9, zmbase
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = *zmbase

            mov     r9, ra
            call    zsv_copy            ; dynamic memory content

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
zdd_mem4:       ds      256
zdd_stack4:     ds      16
zdd_frames4:    ds      36                  ; 1 frame * 36 bytes
zdd_mem5:       ds      256
zdd_stack5:     ds      16
zdd_frames5:    ds      36                  ; 1 frame * 36 bytes
zdd_mem6:       ds      256
zdd_stack6:     ds      16
zdd_frames6:    ds      36                  ; 1 frame * 36 bytes
zdd_mem7:       ds      256
zdd_stack7:     ds      16
zdd_frames7:    ds      36                  ; 1 frame * 36 bytes
zdd_mem8:       ds      256
zdd_stack8:     ds      16
zdd_frames8:    ds      72                  ; 2 frames * 36 bytes
zdd_mem9:       ds      256
zdd_stack9:     ds      16
zdd_frames9:    ds      36                  ; 1 frame * 36 bytes
zdd_mem10:      ds      256
zdd_stack10:    ds      16
zdd_frames10:   ds      36                  ; 1 frame * 36 bytes
zdd_mem11:      ds      256
zdd_stack11:    ds      16
zdd_frames11:   ds      36                  ; 1 frame * 36 bytes
zdd_captured_text: ds   64
zdd_capture_cursor: dw  0
zdd_canned_input: db    "cat dog",0
zdd_save_buf:   ds      300     ; pc(2)+globals_base(2)+eval stack
                                ; len(2)+content+frame stack len(2)+
                                ; content+rand_state(4)+dynamic memory
                                ; len(2)+content (up to check11's own
                                ; 256-byte zminit call) -- comfortably
                                ; oversized
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
                public  zdd_mem4
                public  zdd_stack4
                public  zdd_frames4
                public  zdd_mem5
                public  zdd_stack5
                public  zdd_frames5
                public  zdd_mem6
                public  zdd_stack6
                public  zdd_frames6
                public  zdd_mem7
                public  zdd_stack7
                public  zdd_frames7
                public  zdd_mem8
                public  zdd_stack8
                public  zdd_frames8
                public  zdd_mem9
                public  zdd_stack9
                public  zdd_frames9
                public  zdd_mem10
                public  zdd_stack10
                public  zdd_frames10
                public  zdd_mem11
                public  zdd_stack11
                public  zdd_frames11
                public  zdd_captured_text
                public  zdd_capture_cursor
                public  zdd_canned_input
                public  zdd_save_buf
                public  zdd_results
            endp
