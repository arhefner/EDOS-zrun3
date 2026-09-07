;
; zvar.asm - Z-machine call-frame stack and variable access
;
; Mirrors host/vm_state.c's frame push/pop and the four variable
; access functions (operand vs. indirect, exactly per Z-Machine
; Standard 6.3.4 -- reading/writing variable 0 through the "operand"
; functions pops/pushes the eval stack; the "indirect" functions peek/
; replace its top in place instead, for store/load/inc/dec/inc_chk/
; dec_chk/pull's own variable-NUMBER operand). Built on zstack.asm
; (the eval stack itself, unchanged) and zmem.asm's zmread16/zmwrite16
; (globals, which live in story memory at globals_base + (var-16)*2).
;
; Does NOT yet track a frame's argument_count -- host/vm_state.c has
; the field, but nothing in host/dispatch.c ever reads it (the
; "check_arg_count" opcode that would isn't implemented on either
; side yet), so it's deferred here too rather than carried for no
; reader. Add it back (one more frame-record byte) alongside that
; opcode, on whichever side implements it first.
;
; The call-frame stack is a second, independent bounded region from
; the eval stack, sized by the caller at zvar_init time exactly like
; zstack_init's own RD/RF convention. Each frame is a fixed FRAME_SIZE
; -byte record (return_pc:2, store_variable:1, local_count:1,
; locals:30 -- 15 words, only the first local_count of which are
; meaningful, matching host's own uninitialized-tail behavior --
; stack_base:2), and the frame stack grows the same way zstack.asm's
; does: zv_frame_ptr always points one-past the current top,
; advancing/retreating by FRAME_SIZE per push/pop.
;
; No calls happen inside zvar_frame_push/zvar_frame_pop's own
; bookkeeping (zsptr/zv_* are read directly as data, not through a
; routine call), so nothing there needs special handling across a
; call. zvar_read/zvar_write and their _indirect siblings do call out
; (to zstack_push/zstack_pop/zmread16/zmwrite16/the shared
; zv_local_or_global_read/write helpers below); the variable number
; and, for writes, the value, are the only things that must survive
; one of those, and each site says which register carries it and why
; that register is safe.
;
; Only R7-RD and RF are ever used as scratch (no R1, no RE).
;

#include    include/opcodes.def

            extrn   zsbase
            extrn   zsptr
            extrn   zstack_push
            extrn   zstack_pop
            extrn   zmread16
            extrn   zmwrite16

            extrn   zv_local_or_global_read
            extrn   zv_local_or_global_write

            extrn   zv_globals_base
            extrn   zv_frame_base
            extrn   zv_frame_ptr
            extrn   zv_frame_top

FRAME_RETURN_PC:        equ     0
FRAME_RETURN_PC_BANK:   equ     2       ; the return address's own
                                        ; high word/bank -- a V3 story
                                        ; file over 64K (most of the
                                        ; sample library) can have a
                                        ; routine call happen from
                                        ; beyond the first 64K, so the
                                        ; return address needs the same
                                        ; width as zdisp_pc itself
FRAME_STORE_VARIABLE:   equ     3
FRAME_LOCAL_COUNT:      equ     4
FRAME_LOCALS:            equ     5
FRAME_STACK_BASE:        equ     35
FRAME_SIZE:              equ     37

; zvar_init: RD = globals_base, RF = frame-stack first byte, RC =
; frame-stack exclusive end.
            proc    zvar_init
            mov     rb, zv_globals_base
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb

            mov     rb, zv_frame_base
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb

            mov     rb, zv_frame_ptr
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb                  ; frame_ptr starts == frame_base

            mov     rb, zv_frame_top
            ghi     rc
            str     rb
            inc     rb
            glo     rc
            str     rb
            clc
            rtn
            endp

; zvar_frame_push: RD = return_pc, RA.0 = return_pc's own bank (the
; high word/bank a story file over 64K needs alongside it -- see
; FRAME_RETURN_PC_BANK's own comment), RF = pointer to a local_count-
; word array of already-resolved locals (the routine's own defaults,
; overridden by call arguments -- the caller's job, matching host's
; do_call building this array before calling vm_frame_push), RC.0 =
; store_variable, RC.1 = local_count (0-15). DF=1 if local_count > 15
; or the frame stack is full.
            proc    zvar_frame_push
            glo     ra
            plo     r7                  ; r7.0 = return_pc_bank,
                                        ; captured immediately -- ra
                                        ; itself gets clobbered below
                                        ; (frame_top) before this
                                        ; record is actually written;
                                        ; r7 is free until this same
                                        ; proc's own later local-copy
                                        ; countdown reuses it, well
                                        ; after the write site below

            ghi     rc
            smi     16
            lbdf    zvfp_fail           ; local_count > 15

            mov     rb, zv_frame_ptr
            lda     rb
            phi     r9
            ldn     rb
            plo     r9                  ; r9 = frame_ptr -- this
                                        ; frame's own write address

            mov     r8, r9
            add16   r8, FRAME_SIZE      ; r8 = candidate new frame_ptr

            mov     rb, zv_frame_top
            lda     rb
            phi     ra
            ldn     rb
            plo     ra                  ; ra = frame_top

            mov     rb, ra
            sub16   rb, r8              ; rb = frame_top - candidate;
                                        ; DF=1 (no borrow) means
                                        ; frame_top >= candidate, i.e.
                                        ; still in range (an exact fit,
                                        ; candidate == frame_top, is
                                        ; valid -- the pushed frame
                                        ; occupies up to but not
                                        ; including frame_top, matching
                                        ; frame_top's own documented
                                        ; "exclusive end" meaning, and
                                        ; matching zstack_push's own
                                        ; identical convention, computed
                                        ; the same way round for the
                                        ; same reason). DF=0 (borrow)
                                        ; means frame_top < candidate --
                                        ; genuinely out of range
            lbnf    zvfp_fail

            mov     rb, zv_frame_ptr    ; commit: nothing below can
            ghi     r8                  ; fail, so advance frame_ptr
            str     rb                  ; to the candidate now
            inc     rb
            glo     r8
            str     rb

            mov     r8, r9              ; r8 = write cursor, starts at
                                        ; this frame's base
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8                  ; +0: return_pc
            inc     r8

            glo     r7                  ; d = return_pc_bank, still
                                        ; where it was stashed at entry
            str     r8                  ; +2: return_pc_bank
            inc     r8

            glo     rc
            str     r8                  ; +3: store_variable
            inc     r8

            ghi     rc
            str     r8                  ; +4: local_count
            inc     r8

            ghi     rc
            plo     r7                  ; r7.0 = local_count (copy
                                        ; countdown) -- return_pc_bank's
                                        ; own earlier use of r7 is done
                                        ; by now, safe to repurpose
zvfp_copy:
            glo     r7
            lbz     zvfp_copy_done
            lda     rf                  ; d = source word's high byte,
                                        ; rf++
            str     r8
            inc     r8
            lda     rf                  ; d = source word's low byte,
                                        ; rf++
            str     r8
            inc     r8
            dec     r7
            lbr     zvfp_copy
zvfp_copy_done:

            mov     r8, r9
            add16   r8, FRAME_STACK_BASE ; r8 = this frame's base +34,
                                        ; regardless of how many
                                        ; locals slots were actually
                                        ; written above
            mov     rb, zsptr
            lda     rb
            phi     rc                  ; rc is free again -- store_
                                        ; variable/local_count are
                                        ; already committed to the
                                        ; record
            ldn     rb
            plo     rc                  ; rc = current zsptr
            ghi     rc
            str     r8
            inc     r8
            glo     rc
            str     r8                  ; +34: stack_base = zsptr

            clc
            rtn

zvfp_fail:
            stc
            rtn
            endp

; zvar_frame_pop: returns RD = return_pc, RC.0 = return_pc's own bank
; (the high word/bank a story file over 64K needs alongside it -- see
; FRAME_RETURN_PC_BANK's own comment), RF.0 = store_variable. Also
; truncates the eval stack (zsptr) back to what it was when this
; frame was pushed, discarding any operands the routine left on it.
; DF=1 if the frame stack is empty.
            proc    zvar_frame_pop
            mov     rb, zv_frame_ptr
            lda     rb
            phi     r9
            ldn     rb
            plo     r9                  ; r9 = frame_ptr

            mov     r8, zv_frame_base
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = frame_base

            mov     r8, r9
            sub16   r8, ra              ; r8 = frame_ptr - frame_base
                                        ; (== 0 exactly when empty --
                                        ; frame_ptr never falls below
                                        ; frame_base by construction)
            glo     r8
            lbnz    zvpp_nonempty
            ghi     r8
            lbnz    zvpp_nonempty
            stc
            rtn

zvpp_nonempty:
            mov     r8, r9
            sub16   r8, FRAME_SIZE      ; r8 = the popped frame's base

            mov     rb, zv_frame_ptr
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb                  ; frame_ptr -= FRAME_SIZE

            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = return_pc (+0)
            inc     r8                  ; r8 = +2

            ldn     r8                  ; d = return_pc_bank (+2)
            plo     rc                  ; rc.0 = return_pc_bank
            inc     r8                  ; r8 = +3

            ldn     r8                  ; d = store_variable (+3)
            plo     rf
            add16   r8, 2               ; skip store_variable(+3) and
                                        ; local_count(+4): r8 = +5
                                        ; (FRAME_LOCALS)

            mov     r9, r8
            add16   r9, 30              ; r9 = frame_base + 35
                                        ; (FRAME_STACK_BASE)
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = the saved stack_base

            mov     r9, zsptr
            ghi     ra
            str     r9
            inc     r9
            glo     ra
            str     r9                  ; zsptr = stack_base --
                                        ; unconditionally, unlike
                                        ; host's own "only truncate if
                                        ; deeper than saved" guard.
                                        ; zsptr can only ever be BELOW
                                        ; stack_base here if the
                                        ; routine's own code popped
                                        ; past its call-time baseline
                                        ; -- a malformed story file,
                                        ; not a case any valid V3 game
                                        ; reaches -- so restoring
                                        ; unconditionally is simpler
                                        ; and behaves identically for
                                        ; every real program

            clc
            rtn
            endp

; zv_local_or_global_read (internal): D = variable number, 1-255 (set
; immediately before the call -- variable 0, the eval stack, is
; zvar_read/zvar_read_indirect's own job, not this helper's). Returns
; RF = value. DF=1 for a local number with no active frame, or
; exceeding the active frame's own local_count.
            proc    zv_local_or_global_read
            plo     r9                  ; r9.0 = variable
            smi     16
            lbdf    zlgr_global

            mov     rb, zv_frame_ptr
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; r8 = frame_ptr

            mov     rf, zv_frame_base
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = frame_base

            mov     r7, r8
            sub16   r7, ra
            glo     r7
            lbnz    zlgr_have_frame
            ghi     r7
            lbnz    zlgr_have_frame
            stc
            rtn                         ; no active frame

zlgr_have_frame:
            sub16   r8, FRAME_SIZE      ; r8 = the active frame's base

            glo     r9
            str     r2                  ; m(r2) = variable
            mov     rf, r8
            add16   rf, FRAME_LOCAL_COUNT
            ldn     rf                  ; d = local_count
            sm                          ; d = local_count - variable
            lbnf    zlgr_bad_local      ; DF=0 (borrow): local_count <
                                        ; variable -- out of range

            glo     r9
            shl                         ; d = variable * 2 (variable
                                        ; <= 15, so max 30 -- fits a
                                        ; byte, no overflow)
            adi     3                   ; d = FRAME_LOCALS + variable*2
                                        ; - 2, i.e. the offset of
                                        ; locals[variable-1] (FRAME_
                                        ; LOCALS is 5, so the constant
                                        ; here is 5-2=3 -- shifted from
                                        ; 2 when FRAME_RETURN_PC_BANK
                                        ; pushed every later field
                                        ; forward by one byte)
            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:offset
            mov     rf, r8
            add16   rf, ra              ; rf = the local's address
            lda     rf
            phi     rc
            ldn     rf
            plo     rc
            mov     rf, rc
            clc
            rtn

zlgr_bad_local:
            stc
            rtn

zlgr_global:
            glo     r9
            smi     16
            plo     r8
            ldi     0
            phi     r8
            shl16   r8                  ; r8 = (variable-16)*2

            mov     rd, zv_globals_base
            lda     rd
            phi     r7
            ldn     rd
            plo     r7                  ; r7 = globals_base
            mov     rd, r7
            add16   rd, r8

            call    zmread16
            rtn
            endp

; zv_local_or_global_write (internal): D = variable number, 1-255,
; RF = value (both set immediately before the call). DF=1 on the same
; conditions as zv_local_or_global_read.
            proc    zv_local_or_global_write
            plo     r9                  ; r9.0 = variable
            mov     rc, rf              ; rc = value -- stashed since
                                        ; rf is reused as scratch below

            glo     r9
            smi     16
            lbdf    zlgw_global

            mov     rb, zv_frame_ptr
            lda     rb
            phi     r8
            ldn     rb
            plo     r8

            mov     rf, zv_frame_base
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     r7, r8
            sub16   r7, ra
            glo     r7
            lbnz    zlgw_have_frame
            ghi     r7
            lbnz    zlgw_have_frame
            stc
            rtn

zlgw_have_frame:
            sub16   r8, FRAME_SIZE

            glo     r9
            str     r2
            mov     rf, r8
            add16   rf, FRAME_LOCAL_COUNT
            ldn     rf
            sm
            lbnf    zlgw_bad_local

            glo     r9
            shl
            adi     3                   ; see zv_local_or_global_read's
                                        ; own identical computation for
                                        ; why this is 3, not 2
            plo     ra
            ldi     0
            phi     ra
            mov     rf, r8
            add16   rf, ra
            ghi     rc
            str     rf
            inc     rf
            glo     rc
            str     rf
            clc
            rtn

zlgw_bad_local:
            stc
            rtn

zlgw_global:
            glo     r9
            smi     16
            plo     r8
            ldi     0
            phi     r8
            shl16   r8

            mov     rd, zv_globals_base
            lda     rd
            phi     r7
            ldn     rd
            plo     r7
            mov     rd, r7
            add16   rd, r8

            mov     rf, rc
            call    zmwrite16
            rtn
            endp

; zvar_read: D = variable number (0-255, set immediately before the
; call). Returns RF = value. DF=1 on error (see
; zv_local_or_global_read). Variable 0 is "operand access": pops the
; eval stack.
            proc    zvar_read
            lbz     zvr_stack
            call    zv_local_or_global_read
            rtn
zvr_stack:
            call    zstack_pop
            rtn
            endp

; zvar_write: D = variable number, RF = value (both set immediately
; before the call). DF=1 on error. Variable 0 is "operand access":
; pushes onto the eval stack.
            proc    zvar_write
            lbz     zvw_stack
            call    zv_local_or_global_write
            rtn
zvw_stack:
            call    zstack_push
            rtn
            endp

; zvar_read_indirect: D = variable number. Returns RF = value. DF=1 on
; error. Variable 0 peeks the top of the eval stack without popping it
; (DF=1 if the stack is empty); variables 1-255 behave exactly like
; zvar_read.
            proc    zvar_read_indirect
            lbz     zvri_stack
            call    zv_local_or_global_read
            rtn

zvri_stack:
            mov     r8, zsptr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = zsptr

            mov     r7, zsbase
            lda     r7
            phi     ra
            ldn     r7
            plo     ra                  ; ra = zsbase

            mov     r8, r9
            sub16   r8, ra              ; r8 = zsptr - zsbase (== 0
                                        ; exactly when empty)
            glo     r8
            lbnz    zvri_have_top
            ghi     r8
            lbnz    zvri_have_top
            stc
            rtn

zvri_have_top:
            mov     r8, r9
            sub16   r8, 2               ; r8 = the top item's address
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            clc
            rtn
            endp

; zvar_write_indirect: D = variable number, RF = value. DF=1 on error.
; Variable 0 replaces the top of the eval stack in place, without
; pushing (DF=1 if the stack is empty); variables 1-255 behave exactly
; like zvar_write.
            proc    zvar_write_indirect
            lbz     zvwi_stack
            call    zv_local_or_global_write
            rtn

zvwi_stack:
            mov     rc, rf              ; rc = value -- stashed since
                                        ; rf is reused as scratch below
            mov     r8, zsptr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9

            mov     r7, zsbase
            lda     r7
            phi     ra
            ldn     r7
            plo     ra

            mov     r8, r9
            sub16   r8, ra
            glo     r8
            lbnz    zvwi_have_top
            ghi     r8
            lbnz    zvwi_have_top
            stc
            rtn

zvwi_have_top:
            mov     r8, r9
            sub16   r8, 2
            ghi     rc
            str     r8
            inc     r8
            glo     rc
            str     r8
            clc
            rtn
            endp

            proc    _zvar_data
zv_globals_base:    dw      0
zv_frame_base:      dw      0
zv_frame_ptr:       dw      0
zv_frame_top:       dw      0
                public  zv_globals_base
                public  zv_frame_base
                public  zv_frame_ptr
                public  zv_frame_top
            endp
