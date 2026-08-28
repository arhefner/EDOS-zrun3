;
; zdispatch.asm - V3 opcode execution engine (proof-of-concept slice)
;
; Mirrors host/dispatch.c's own first proof-of-concept milestone: 2OP
; je/store/add/sub, 1OP jz/ret/jump, 0OP rtrue/rfalse/quit, and VAR
; call. Deliberately does not yet cover print/new_line (text output
; needs its own design pass -- how a "print"-family opcode reaches an
; actual screen depends on the platform layer, e.g. K_TYPE under
; ELF-DOS vs. a bare-metal diag's own capture buffer, and host's own
; ctx->emit callback has no direct 1802 equivalent yet) or any other
; opcode; unrecognized opcodes fail with DF=1, exactly like
; zdecode_instruction does for an unrecognized instruction.
;
; zdisp_step (no arguments -- uses zdisp_pc) decodes and executes
; exactly one instruction, advancing zdisp_pc (or branching/calling/
; returning as the opcode itself dictates). Built on zdecode_instruction
; (lib/zdecode.asm) and zvar.asm's frame/variable primitives.
;
; Every zvar_* call clobbers nearly every register (see zvar.asm's own
; header -- its calls into zstack/zmread16/zmwrite16 spread the
; footprint across all of R7-RD/RF between the two), so nothing this
; module needs to survive one lives in a register; it lives in one of
; the zdisp_* scratch fields below, reloaded fresh after any call --
; the same discipline zparse.asm documents for the same reason. The
; only exception is a value used and discarded entirely between two
; calls, which is called out at each site.
;
; zdisp_instr (decode's own output buffer) is a single fixed buffer,
; not a parameter passed around, since zdisp_step only ever has one
; instruction "in flight" at a time -- every opcode handler reads it
; via direct zdisp_instr+ZDI_* addressing (a compile-time constant,
; unlike zdecode.asm's own zde_fieldptr, which exists only because
; *that* module's buffer address is a caller-supplied runtime
; parameter).
;
; A crucial 1802-specific trap, worth restating here because it has
; caused real bugs even after being "known" -- and in a more complete
; form than first documented: BOTH forms of `mov` clobber D, not just
; the immediate one. `mov Rd, N` (register := immediate or symbol
; address) does it via its own internal LDIs; `mov Rd, Rs` (register-
; to-register) does it too, less obviously -- its expansion is GHI Rs/
; PHI Rd/GLO Rs/PLO Rd, and that trailing GLO Rs leaves D holding Rs's
; own low byte, not whatever D held beforehand. A `mov Rd, Rs` used to
; carry a value into RF while some *other* value already sat in D for
; an upcoming call (e.g. a variable number about to be D's own
; parameter) silently destroys it. Every `ldi <scalar>`/`ldn`/`glo`
; that sets D for an upcoming `call`'s parameter is placed as the LAST
; d-setting instruction before that call, with no intervening `mov` of
; either form -- see include/zdecode.inc-based field reads throughout,
; which use `mov rX, zdisp_instr+OFFSET` freely wherever D doesn't
; need to survive past that point, and zds_store for the fix once this
; exact trap was hit for real (D silently became the store's own
; *value* operand's low byte instead of surviving as the variable
; number, because the register-to-register mov setting RF ran after
; D had already been loaded, not before).
;
; Only R7-RD and RF are ever used as scratch (no R1, no RE).
;

#include    include/opcodes.def
#include    include/zdecode.inc

            extrn   zmread
            extrn   zmread16
            extrn   zdecode_instruction
            extrn   zvar_read
            extrn   zvar_write
            extrn   zvar_write_indirect
            extrn   zvar_frame_push
            extrn   zvar_frame_pop

            extrn   zdisp_branch
            extrn   zdisp_return
            extrn   zdisp_do_call

            extrn   zdisp_pc
            extrn   zdisp_quit
            extrn   zdisp_i
            extrn   zdisp_next_pc
            extrn   zdisp_value
            extrn   zdisp_routine_addr
            extrn   zdisp_local_count
            extrn   zdisp_instr
            extrn   zdisp_operand
            extrn   zdisp_locals

; zdisp_step: no arguments (uses zdisp_pc). Returns DF=1 for a decode
; error or an opcode this slice doesn't recognize yet.
            proc    zdisp_step
            mov     r8, zdisp_pc
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = current pc

            mov     rf, zdisp_instr
            call    zdecode_instruction
            lbdf    zds_error

; next_pc = instr.addr + instr.length, both already written by decode
            mov     rf, zdisp_instr+ZDI_ADDR
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = addr
            mov     rf, zdisp_instr+ZDI_LENGTH
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = length
            add16   r8, r9              ; r8 = next_pc

            mov     rf, zdisp_next_pc
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf

            mov     rf, zdisp_pc        ; commit the default fallthrough
            ghi     r8                  ; now -- every opcode handler
            str     rf                  ; below that branches/calls/
            inc     rf                  ; returns overrides this later
            glo     r8                  ; in the same zdisp_step call
            str     rf

; resolve operands: zdisp_operand[i] = operand_types[i]==VARIABLE ?
; zvar_read(operands[i]) : operands[i], for i in 0..operand_count-1
            mov     rf, zdisp_i
            ldi     0
            str     rf

zds_resolve_loop:
            mov     rf, zdisp_instr+ZDI_OPERAND_COUNT
            ldn     rf                  ; d = operand_count
            str     r2
            mov     rf, zdisp_i
            ldn     rf                  ; d = i
            xor                         ; zero iff i == operand_count
            lbz     zds_resolve_done

            mov     rf, zdisp_i
            ldn     rf
            adi     ZDI_OPERAND_TYPES
            plo     r8
            ldi     0
            phi     r8
            mov     rf, zdisp_instr
            add16   rf, r8
            ldn     rf                  ; d = operand_types[i]
            xri     2                   ; == VARIABLE?
            lbnz    zds_resolve_const

; variable operand: operands[i]'s own raw value is the variable
; NUMBER (already zero-extended to a word by decode); resolve it
            mov     rf, zdisp_i
            ldn     rf
            shl
            adi     ZDI_OPERANDS+1      ; +1: the LOW byte -- operands[i]
                                        ; is stored high-byte-first like
                                        ; every other resolved word, so
                                        ; its high byte (always 0 for a
                                        ; variable number) is not what
                                        ; we want (the same mistake
                                        ; zds_store's own operand[0]
                                        ; read had -- see that fix's
                                        ; own comment). Only variable 0
                                        ; happened to read correctly
                                        ; either way, since its high
                                        ; and low bytes are both 0
            plo     r8
            ldi     0
            phi     r8
            mov     rf, zdisp_instr
            add16   rf, r8
            ldn     rf                  ; d = the variable number
            call    zvar_read           ; rf = resolved value, df=err
            lbdf    zds_error
            lbr     zds_resolve_store

zds_resolve_const:
            mov     rf, zdisp_i
            ldn     rf
            shl
            adi     ZDI_OPERANDS
            plo     r8
            ldi     0
            phi     r8
            mov     r9, zdisp_instr
            add16   r9, r8
            lda     r9
            phi     rf
            ldn     r9
            plo     rf                  ; rf = the raw constant value

zds_resolve_store:
            mov     r9, rf              ; r9 = value -- stashed before
                                        ; rf/r8 get reused as scratch
                                        ; for the destination offset
            mov     rf, zdisp_i
            ldn     rf
            shl
            plo     r8
            ldi     0
            phi     r8
            mov     rf, zdisp_operand
            add16   rf, r8
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf

            mov     rf, zdisp_i
            ldn     rf
            adi     1
            str     rf                  ; zdisp_i += 1
            lbr     zds_resolve_loop

zds_resolve_done:
; dispatch on category, then opcode
            mov     rf, zdisp_instr+ZDI_CATEGORY
            ldn     rf
            xri     ZDI_CAT_2OP
            lbz     zds_2op
            mov     rf, zdisp_instr+ZDI_CATEGORY
            ldn     rf
            xri     ZDI_CAT_1OP
            lbz     zds_1op
            mov     rf, zdisp_instr+ZDI_CATEGORY
            ldn     rf
            xri     ZDI_CAT_0OP
            lbz     zds_0op
            mov     rf, zdisp_instr+ZDI_CATEGORY
            ldn     rf
            xri     ZDI_CAT_VAR
            lbz     zds_var
            stc
            rtn

zds_2op:
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     1
            lbz     zds_je
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     13
            lbz     zds_store
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     20
            lbz     zds_add
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     21
            lbz     zds_sub
            stc
            rtn

zds_1op:
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            lbz     zds_jz              ; opcode 0
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     11
            lbz     zds_ret
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     12
            lbz     zds_jump
            stc
            rtn

zds_0op:
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            lbz     zds_rtrue           ; opcode 0
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     1
            lbz     zds_rfalse
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     10
            lbz     zds_quit
            stc
            rtn

zds_var:
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            lbz     zds_call            ; opcode 0
            stc
            rtn

; ---- je: true if any later operand equals the first ----
zds_je:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0]

            mov     rf, zdisp_i
            ldi     1
            str     rf                  ; zdisp_i = 1 (compare from
                                        ; the second operand onward)
zdje_loop:
            mov     rf, zdisp_instr+ZDI_OPERAND_COUNT
            ldn     rf
            str     r2
            mov     rf, zdisp_i
            ldn     rf
            sm                          ; d = i - operand_count
            lbdf    zdje_no_match       ; i >= operand_count: exhausted

            mov     rf, zdisp_i
            ldn     rf
            shl
            plo     r8
            ldi     0
            phi     r8
            mov     rf, zdisp_operand
            add16   rf, r8
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[i]

            glo     ra
            str     r2
            glo     r9
            xor
            lbnz    zdje_next
            ghi     ra
            str     r2
            ghi     r9
            xor
            lbz     zdje_match

zdje_next:
            mov     rf, zdisp_i
            ldn     rf
            adi     1
            str     rf
            lbr     zdje_loop

zdje_match:
            ldi     1
            lbr     zdje_branch
zdje_no_match:
            ldi     0
zdje_branch:
            call    zdisp_branch
            rtn

; ---- store: operand[0] is a variable NUMBER (indirect access) ----
zds_store:
            mov     rf, zdisp_operand+2
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[1] (the value)

            mov     rf, r9              ; rf = value -- set FIRST: a
                                        ; register-to-register mov does
                                        ; NOT preserve d the way a
                                        ; register-immediate mov's
                                        ; cousin trap suggests it might
                                        ; -- "9$2 B$1 8$2 A$1" (GHI Rs/
                                        ; PHI Rd/GLO Rs/PLO Rd) ends
                                        ; with GLO, so d is left holding
                                        ; Rs's own low byte, not
                                        ; whatever d held before. Doing
                                        ; this mov first, before d is
                                        ; loaded with the variable
                                        ; number below, avoids relying
                                        ; on d surviving it
            mov     r8, zdisp_operand+1 ; +1: the LOW byte -- operand[0]
                                        ; is stored high-byte-first
                                        ; like every other resolved
                                        ; word, so its high byte (at
                                        ; +0, always 0 for a variable
                                        ; number) is not what we want
            ldn     r8                  ; d = operand[0]'s low byte
                                        ; (the variable number), set
                                        ; LAST, immediately before the
                                        ; call
            call    zvar_write_indirect
            rtn

; ---- add/sub: store the arithmetic result ----
zds_add:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0]
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1]
            add16   r9, ra              ; r9 = operand[0] + operand[1]
            mov     rf, r9
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zds_sub:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0]
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1]
            sub16   r9, ra              ; r9 = operand[0] - operand[1]
            mov     rf, r9
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- jz: branch if operand[0] == 0 ----
zds_jz:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            glo     r9
            lbnz    zdjz_nonzero
            ghi     r9
            lbnz    zdjz_nonzero
            ldi     1
            lbr     zdjz_branch
zdjz_nonzero:
            ldi     0
zdjz_branch:
            call    zdisp_branch
            rtn

; ---- ret: return operand[0] ----
zds_ret:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, r9
            call    zdisp_return
            rtn

; ---- jump: unconditional, same "+offset-2" rule as a taken branch,
; but the operand is a plain signed word, not branch data ----
zds_jump:
            mov     rf, zdisp_instr+ZDI_ADDR
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = addr
            mov     rf, zdisp_instr+ZDI_LENGTH
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = length
            add16   r8, r9              ; r8 = after

            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (signed)
            add16   r8, r9
            sub16   r8, 2               ; r8 = after + operand[0] - 2

            mov     rf, zdisp_pc
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf
            clc
            rtn

; ---- rtrue/rfalse: return a literal 1/0 ----
zds_rtrue:
            mov     rf, 1
            call    zdisp_return
            rtn

zds_rfalse:
            mov     rf, 0
            call    zdisp_return
            rtn

; ---- quit ----
zds_quit:
            mov     rf, zdisp_quit
            ldi     1
            str     rf
            clc
            rtn

; ---- call ----
zds_call:
            call    zdisp_do_call
            rtn

zds_error:
            stc
            rtn
            endp

; zdisp_branch (internal): D = condition, 0 or 1 (set immediately
; before the call). Reads instr.branch_on_true/branch_offset/addr/
; length from zdisp_instr. If the branch is taken, either delegates to
; zdisp_return (offset 0/1 mean return false/true) or sets zdisp_pc to
; addr+length+offset-2; if not taken, zdisp_pc keeps the default
; fallthrough zdisp_step already committed.
            proc    zdisp_branch
            plo     r7                  ; r7.0 = condition -- no call
                                        ; happens before this is used,
                                        ; on either path
            mov     rf, zdisp_instr+ZDI_BRANCH_ON_TRUE
            ldn     rf
            str     r2
            glo     r7
            xor                         ; zero iff condition matches
                                        ; branch_on_true
            lbnz    zdb_not_taken

            mov     rf, zdisp_instr+ZDI_BRANCH_OFFSET
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = branch_offset

            glo     r8
            lbnz    zdb_not_zero
            ghi     r8
            lbnz    zdb_not_zero
            mov     rf, 0
            call    zdisp_return
            rtn

zdb_not_zero:
            glo     r8
            xri     1
            lbnz    zdb_jump
            ghi     r8
            lbnz    zdb_jump
            mov     rf, 1
            call    zdisp_return
            rtn

zdb_jump:
            mov     rf, zdisp_instr+ZDI_ADDR
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = addr
            mov     rf, zdisp_instr+ZDI_LENGTH
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = length
            add16   r9, ra              ; r9 = after
            add16   r9, r8              ; r9 = after + offset
            sub16   r9, 2               ; r9 = after + offset - 2

            mov     rf, zdisp_pc
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf
            clc
            rtn

zdb_not_taken:
            clc
            rtn
            endp

; zdisp_return (internal): RF = return value (set immediately before
; the call). Pops the current frame, writes the value into the popped
; frame's own store_variable, and sets zdisp_pc to its return_pc.
; DF=1 if there's no active frame to pop.
            proc    zdisp_return
            mov     r7, zdisp_value
            ghi     rf
            str     r7
            inc     r7
            glo     rf
            str     r7                  ; zdisp_value = the return
                                        ; value -- stashed in memory,
                                        ; since zvar_frame_pop's own
                                        ; clobber footprint is wide

            call    zvar_frame_pop      ; rd = return_pc, rf.0 =
                                        ; store_variable -- NOT in d;
                                        ; zvar_frame_pop's own internal
                                        ; bookkeeping (stack_base
                                        ; restore) runs more arithmetic
                                        ; after setting rf.0, so d no
                                        ; longer holds it by the time
                                        ; this returns
            lbdf    zdret_fail

            glo     rf                  ; d = store_variable, from
                                        ; rf.0 (not d)
            plo     r9                  ; r9.0 = store_variable -- no
                                        ; call happens before this is
                                        ; used below

            mov     r8, zdisp_pc
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8                  ; zdisp_pc = return_pc

            mov     rf, zdisp_value
            lda     rf
            phi     rc
            ldn     rf
            plo     rc                  ; rc = the stashed return value
            mov     rf, rc              ; rf = value -- this DOES leave
                                        ; d holding rc's own low byte
                                        ; (mov Rd,Rs ends with GLO Rs,
                                        ; not a no-op for d the way
                                        ; mov Rd,N's own clobber does),
                                        ; but that's fine since d is
                                        ; set fresh again right below,
                                        ; before it's actually needed
            glo     r9                  ; d = store_variable, set LAST
            call    zvar_write
            rtn

zdret_fail:
            stc
            rtn
            endp

; zdisp_do_call (internal): builds the routine's locals array (its
; own defaults from the story, overridden by the call's own
; arguments) and pushes a new frame, using zdisp_operand[0] as the
; packed routine address and zdisp_operand[1..] as the arguments (per
; zdisp_instr[ZDI_OPERAND_COUNT]). Sets zdisp_pc to the routine's
; first instruction. DF=1 on any failure (bad routine header, more
; than 15 locals, frame stack full).
            proc    zdisp_do_call
            mov     rf, zdisp_operand
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = operand[0]
            shl16   r8                  ; r8 = routine_addr (V3
                                        ; packing: *2)

            mov     r9, zdisp_routine_addr
            ghi     r8
            str     r9
            inc     r9
            glo     r8
            str     r9                  ; zdisp_routine_addr =
                                        ; routine_addr

            mov     rd, r8
            call    zmread              ; d = local_count byte, df=err
            lbdf    zdc_fail

            plo     r9                  ; r9.0 = local_count -- stashed
                                        ; in a register, since `mov
                                        ; rX,symbol`'s own internal
                                        ; ldi's would clobber d before
                                        ; a direct `str` could use it
            mov     r8, zdisp_local_count
            glo     r9
            str     r8                  ; zdisp_local_count = local_count

            glo     r9
            smi     16
            lbdf    zdc_fail            ; local_count > 15: reject

            mov     rf, zdisp_i
            ldi     0
            str     rf

zdc_loop:
            mov     rf, zdisp_local_count
            ldn     rf
            str     r2
            mov     rf, zdisp_i
            ldn     rf
            sm                          ; d = i - local_count (== 0
                                        ; exactly when i has reached
                                        ; local_count, since i only
                                        ; ever increases by 1 from 0)
            lbz     zdc_loop_done

; default = zmread16(routine_addr + 1 + i*2)
            mov     rf, zdisp_i
            ldn     rf
            shl                         ; d = i*2
            plo     r8
            ldi     0
            phi     r8                  ; r8 = 0:(i*2)
            mov     r9, zdisp_routine_addr
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = routine_addr
            add16   ra, 1
            add16   ra, r8              ; ra = routine_addr+1+i*2
            mov     rd, ra
            call    zmread16            ; rf = default value, df=err
            lbdf    zdc_fail

            mov     r9, zdisp_value
            ghi     rf
            str     r9
            inc     r9
            glo     rf
            str     r9                  ; zdisp_value = default
                                        ; (tentative)

; if an argument was supplied for local i (i+1 < operand_count),
; override zdisp_value with zdisp_operand[i+1]
            mov     rf, zdisp_instr+ZDI_OPERAND_COUNT
            ldn     rf
            str     r2
            mov     rf, zdisp_i
            ldn     rf
            adi     1
            sm                          ; d = (i+1) - operand_count;
                                        ; DF=1 (no borrow) means
                                        ; i+1 >= operand_count -- no
                                        ; argument for this local
            lbdf    zdc_use_default

            mov     rf, zdisp_i
            ldn     rf
            adi     1
            shl                         ; d = (i+1)*2
            plo     r8
            ldi     0
            phi     r8
            mov     r9, zdisp_operand
            add16   r9, r8
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = the argument value
            mov     r9, zdisp_value
            ghi     ra
            str     r9
            inc     r9
            glo     ra
            str     r9                  ; zdisp_value = argument
                                        ; (override)

zdc_use_default:
            mov     rf, zdisp_i
            ldn     rf
            shl
            plo     r8
            ldi     0
            phi     r8
            mov     r9, zdisp_locals
            add16   r9, r8
            mov     rf, zdisp_value
            lda     rf
            phi     ra
            ldn     rf
            plo     ra
            ghi     ra
            str     r9
            inc     r9
            glo     ra
            str     r9                  ; zdisp_locals[i] = zdisp_value

            mov     rf, zdisp_i
            ldn     rf
            adi     1
            str     rf                  ; zdisp_i += 1
            lbr     zdc_loop

zdc_loop_done:
            mov     r8, zdisp_next_pc
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = return_pc

            mov     rf, zdisp_locals

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            plo     rc                  ; rc.0 = store_variable
            mov     r8, zdisp_local_count
            ldn     r8
            phi     rc                  ; rc.1 = local_count

            call    zvar_frame_push
            lbdf    zdc_fail

; pc = routine_addr + 1 + local_count*2
            mov     r8, zdisp_local_count
            ldn     r8
            shl
            plo     r9
            ldi     0
            phi     r9                  ; r9 = local_count*2
            mov     r8, zdisp_routine_addr
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = routine_addr
            add16   ra, 1
            add16   ra, r9              ; ra = routine_addr+1+
                                        ; local_count*2

            mov     r8, zdisp_pc
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8
            clc
            rtn

zdc_fail:
            stc
            rtn
            endp

            proc    _zdispatch_data
zdisp_pc:            dw      0
zdisp_quit:           db      0
zdisp_i:              db      0
zdisp_next_pc:         dw      0
zdisp_value:            dw      0
zdisp_routine_addr:      dw      0
zdisp_local_count:        db      0
zdisp_instr:               ds      ZDI_SIZE
zdisp_operand:              ds      8       ; 4 resolved operand words
zdisp_locals:                ds      30      ; up to 15 locals
                public  zdisp_pc
                public  zdisp_quit
                public  zdisp_i
                public  zdisp_next_pc
                public  zdisp_value
                public  zdisp_routine_addr
                public  zdisp_local_count
                public  zdisp_instr
                public  zdisp_operand
                public  zdisp_locals
            endp
