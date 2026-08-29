;
; zdispatch.asm - V3 opcode execution engine (proof-of-concept slice)
;
; Mirrors host/dispatch.c's own first proof-of-concept milestone: 2OP
; je/store/add/sub, 1OP jz/ret/jump, 0OP rtrue/rfalse/print/print_ret/
; quit/new_line, and VAR call. Any other opcode fails with DF=1,
; exactly like zdecode_instruction does for an unrecognized
; instruction.
;
; print-family output goes through zdisp_emit_string (RF = a NUL-
; terminated buffer, set immediately before the call) -- one narrow
; platform hook, per docs/ARCHITECTURE.md's "core never calls an
; ELF-DOS entry point directly" rule, with its actual implementation
; chosen at LINK time, not runtime: lib/zdispemit.asm's real one is a
; thin passthrough to K_MSG for an eventual ELF-DOS interpreter build;
; diag/zdispatchdiag.asm links in a capture-buffer version instead, so
; print/new_line stay bare-metal testable without the ELF-DOS kernel
; (which K_MSG itself requires) and so a check can assert on the exact
; captured bytes rather than only "did it crash". This shape doesn't
; match host's own ctx->emit -- a per-character callback ztext_decode
; drives directly -- because zdec_decode (the 1802 Z-text decoder)
; fills a caller-supplied buffer rather than calling back per
; character; since zdec_decode's own output is already NUL-terminated,
; the whole decoded string goes to zdisp_emit_string in one call
; (zdisp_print_inline), never walked a character at a time. icall.asm
; (this project's actual indirect-call mechanism) is deliberately not
; used here -- it exists for genuinely runtime-dynamic module loading,
; which this isn't; both zdisp_emit_string implementations are known
; at link time, matching lib/lineedit.asm's own precedent for
; preferring a plain call over icall when nothing is truly dynamic.
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
            extrn   zmbase
            extrn   zdecode_instruction
            extrn   zdec_decode
            extrn   zvar_read
            extrn   zvar_read_indirect
            extrn   zvar_write
            extrn   zvar_write_indirect
            extrn   zvar_frame_push
            extrn   zvar_frame_pop
            extrn   zdisp_emit_string

            extrn   zobj_get_parent
            extrn   zobj_get_sibling
            extrn   zobj_get_child
            extrn   zobj_test_attr
            extrn   zobj_set_attr
            extrn   zobj_clear_attr
            extrn   zobj_remove
            extrn   zobj_insert
            extrn   zprop_get_addr
            extrn   zprop_get_len
            extrn   zprop_get
            extrn   zprop_get_next

            extrn   zdisp_branch
            extrn   zdisp_return
            extrn   zdisp_do_call
            extrn   zdisp_print_inline
            extrn   zdisp_store_and_branch_nonzero
            extrn   zdisp_slt

            extrn   zdisp_pc
            extrn   zdisp_quit
            extrn   zdisp_i
            extrn   zdisp_next_pc
            extrn   zdisp_value
            extrn   zdisp_value2
            extrn   zdisp_routine_addr
            extrn   zdisp_local_count
            extrn   zdisp_instr
            extrn   zdisp_operand
            extrn   zdisp_locals
            extrn   zdisp_text_buf
            extrn   zdisp_newline_buf

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
            xri     2
            lbz     zds_jl
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     3
            lbz     zds_jg
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     4
            lbz     zds_dec_chk
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     5
            lbz     zds_inc_chk
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     6
            lbz     zds_jin
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     7
            lbz     zds_test
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     8
            lbz     zds_or
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     9
            lbz     zds_and
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     10
            lbz     zds_test_attr
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     11
            lbz     zds_set_attr
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     12
            lbz     zds_clear_attr
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     13
            lbz     zds_store
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     14
            lbz     zds_insert_obj
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     17
            lbz     zds_get_prop
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     18
            lbz     zds_get_prop_addr
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     19
            lbz     zds_get_next_prop
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
            xri     1
            lbz     zds_get_sibling
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     2
            lbz     zds_get_child
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     3
            lbz     zds_get_parent
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     4
            lbz     zds_get_prop_len
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     5
            lbz     zds_inc
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     6
            lbz     zds_dec
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     9
            lbz     zds_remove_obj
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     11
            lbz     zds_ret
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     12
            lbz     zds_jump
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     14
            lbz     zds_load
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     15
            lbz     zds_not
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
            xri     2
            lbz     zds_print
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     3
            lbz     zds_print_ret
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     10
            lbz     zds_quit
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     11
            lbz     zds_new_line
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

; ---- jl / jg: branch on signed 16-bit comparison, via the shared
; zdisp_slt helper ----
zds_jl:
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

            mov     rd, r9
            mov     rf, ra
            call    zdisp_slt           ; d = (operand[0] < operand[1])
            call    zdisp_branch
            rtn

zds_jg:
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

            mov     rd, ra
            mov     rf, r9
            call    zdisp_slt           ; d = (operand[1] < operand[0])
                                        ; == (operand[0] > operand[1])
            call    zdisp_branch
            rtn

; ---- dec_chk / inc_chk: operand[0] is a variable NUMBER (its own
; resolved value's low byte, re-read fresh from zdisp_operand+1
; before each call below rather than trusted in a register, since
; zvar_read_indirect/zvar_write_indirect clobber nearly everything --
; see zvar.asm's own header), adjusted indirectly by 1; branch on a
; signed comparison against operand[1] ----
zds_dec_chk:
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (threshold)
            mov     r8, zdisp_value2
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zdisp_value2 = threshold

            mov     rf, zdisp_operand+1
            ldn     rf                  ; d = variable number
            call    zvar_read_indirect  ; rf = current, df=err
            lbdf    zds_error

            sub16   rf, 1               ; rf = updated = current - 1
            mov     r8, zdisp_value
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value = updated

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = updated, reloaded fresh
            mov     r8, zdisp_operand+1
            ldn     r8                  ; d = variable number (re-read,
                                        ; last before the call)
            call    zvar_write_indirect
            lbdf    zds_error

            mov     r8, zdisp_value
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = updated
            mov     r8, zdisp_value2
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = threshold
            call    zdisp_slt           ; d = (updated < threshold)
            call    zdisp_branch
            rtn

zds_inc_chk:
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (threshold)
            mov     r8, zdisp_value2
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zdisp_value2 = threshold

            mov     rf, zdisp_operand+1
            ldn     rf                  ; d = variable number
            call    zvar_read_indirect  ; rf = current, df=err
            lbdf    zds_error

            add16   rf, 1               ; rf = updated = current + 1
            mov     r8, zdisp_value
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value = updated

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = updated, reloaded fresh
            mov     r8, zdisp_operand+1
            ldn     r8                  ; d = variable number (re-read,
                                        ; last before the call)
            call    zvar_write_indirect
            lbdf    zds_error

            mov     r8, zdisp_value2
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = threshold
            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = updated
            call    zdisp_slt           ; d = (threshold < updated)
                                        ; == (updated > threshold)
            call    zdisp_branch
            rtn

; ---- jin: branch if operand[0]'s parent == operand[1] ----
zds_jin:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (object)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (expected
                                        ; parent)

            mov     rd, r9
            call    zobj_get_parent     ; d = actual parent
            str     r2                  ; m(r2) = actual parent
            glo     ra
            xor                          ; zero iff actual == expected
            lbnz    zdjin_false
            ldi     1
            lbr     zdjin_branch
zdjin_false:
            ldi     0
zdjin_branch:
            call    zdisp_branch
            rtn

; ---- test: branch if every bit set in operand[1] is also set in
; operand[0] ----
zds_test:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (bitmap)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (flags)

            ghi     ra
            str     r2
            ghi     r9
            and
            phi     rc                  ; rc.hi = bitmap.hi & flags.hi
            glo     ra
            str     r2
            glo     r9
            and
            plo     rc                  ; rc.lo = bitmap.lo & flags.lo

            ghi     rc
            str     r2
            ghi     ra
            xor
            lbnz    zdt_false
            glo     rc
            str     r2
            glo     ra
            xor
            lbnz    zdt_false
            ldi     1
            lbr     zdt_branch
zdt_false:
            ldi     0
zdt_branch:
            call    zdisp_branch
            rtn

; ---- or / and: bitwise, store ----
zds_or:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            ghi     ra
            str     r2
            ghi     r9
            or
            phi     rc
            glo     ra
            str     r2
            glo     r9
            or
            plo     rc

            mov     rf, rc
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zds_and:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            ghi     ra
            str     r2
            ghi     r9
            and
            phi     rc
            glo     ra
            str     r2
            glo     r9
            and
            plo     rc

            mov     rf, rc
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

; ---- print: decode and emit this instruction's own inline text ----
zds_print:
            call    zdisp_print_inline
            rtn

; ---- print_ret: print, then a newline, then return true ----
zds_print_ret:
            call    zdisp_print_inline
            lbdf    zds_error
            mov     rf, zdisp_newline_buf
            call    zdisp_emit_string
            mov     rf, 1
            call    zdisp_return
            rtn

; ---- new_line ----
zds_new_line:
            mov     rf, zdisp_newline_buf
            call    zdisp_emit_string
            clc
            rtn

; ---- test_attr: RD=object, D=attribute -> DF=is_set, branch ----
zds_test_attr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = object
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = attribute

            mov     rd, r9
            glo     ra
            call    zobj_test_attr      ; df = is_set
            lbdf    zdta_set
            ldi     0
            lbr     zdta_branch
zdta_set:
            ldi     1
zdta_branch:
            call    zdisp_branch
            rtn

; ---- set_attr / clear_attr: RD=object, D=attribute, no return ----
zds_set_attr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zobj_set_attr
            rtn

zds_clear_attr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zobj_clear_attr
            rtn

; ---- insert_obj: RD=object, D=destination, no return ----
zds_insert_obj:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zobj_insert
            rtn

; ---- get_prop: RD=object, D=property -> RF=value, store ----
zds_get_prop:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zprop_get           ; rf = value
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- get_prop_addr: RD=object, D=property -> RF=real address (0 if
; absent), translated to a guest/story address before storing --
; zprop_get_addr, like every zobj_*/zprop_* routine, operates on real
; memory directly (see zobj.asm's own zobase), but the Z-machine
; variable this gets stored into is read back as a guest address by
; whatever opcode uses it next (get_prop_len, loadb/storeb, ...) ----
zds_get_prop_addr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zprop_get_addr      ; rf = real address (0 if
                                        ; absent)
            glo     rf
            lbnz    zdgpa_translate
            ghi     rf
            lbnz    zdgpa_translate
            lbr     zdgpa_store         ; absent: store 0 as-is, no
                                        ; translation (0 - zmbase
                                        ; would be the wrong thing)

zdgpa_translate:
            mov     r8, zmbase
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = zmbase
            sub16   rf, r9              ; rf = real - zmbase = guest
                                        ; address

zdgpa_store:
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- get_next_prop: RD=object, D=property -> D=next property number,
; store; DF=1 if `property` wasn't actually one of the object's own ----
zds_get_next_prop:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra

            mov     rd, r9
            glo     ra
            call    zprop_get_next      ; d = next property, df=err
            lbdf    zds_error

            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:next_property

            mov     rf, ra
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- get_sibling / get_child: RD=object -> D=sibling/child, store,
; branch if nonzero ----
zds_get_sibling:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rd, r9
            call    zobj_get_sibling    ; d = sibling
            call    zdisp_store_and_branch_nonzero
            rtn

zds_get_child:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rd, r9
            call    zobj_get_child      ; d = child
            call    zdisp_store_and_branch_nonzero
            rtn

; ---- get_parent: RD=object -> D=parent, store (no branch) ----
zds_get_parent:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rd, r9
            call    zobj_get_parent     ; d = parent
            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:parent

            mov     rf, ra
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- get_prop_len: operand[0] is a property's own data address (a
; guest/story address, as every property address a game holds is --
; see get_prop_addr's own note), translated to real memory before the
; call, since zprop_get_len (like every zobj_*/zprop_* routine)
; expects one ----
zds_get_prop_len:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (guest
                                        ; address, or 0)

            glo     r9
            lbnz    zdgpl_translate
            ghi     r9
            lbnz    zdgpl_translate
            lbr     zdgpl_have_addr     ; address 0: leave as-is (its
                                        ; own "no property" case,
                                        ; matching zprop_get_len's own
                                        ; special-cased 0 -- adding
                                        ; zmbase to it would be wrong)

zdgpl_translate:
            mov     r8, zmbase
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = zmbase
            add16   r9, ra              ; r9 = real address

zdgpl_have_addr:
            mov     rd, r9
            call    zprop_get_len       ; d = length
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:length
            mov     rf, rc

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- remove_obj: RD=object, no return ----
zds_remove_obj:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rd, r9
            call    zobj_remove
            rtn

; ---- inc / dec: operand[0] is a variable NUMBER (re-read fresh from
; zdisp_operand+1 before each call, same reasoning as dec_chk/inc_chk
; above), adjusted indirectly by 1; no store, no branch ----
zds_inc:
            mov     rf, zdisp_operand+1
            ldn     rf                  ; d = variable number
            call    zvar_read_indirect  ; rf = current, df=err
            lbdf    zds_error

            add16   rf, 1               ; rf = updated
            mov     r8, zdisp_value
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value = updated

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            mov     r8, zdisp_operand+1
            ldn     r8                  ; d = variable number (re-read,
                                        ; last before the call)
            call    zvar_write_indirect
            rtn

zds_dec:
            mov     rf, zdisp_operand+1
            ldn     rf                  ; d = variable number
            call    zvar_read_indirect  ; rf = current, df=err
            lbdf    zds_error

            sub16   rf, 1               ; rf = updated
            mov     r8, zdisp_value
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value = updated

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            mov     r8, zdisp_operand+1
            ldn     r8                  ; d = variable number (re-read,
                                        ; last before the call)
            call    zvar_write_indirect
            rtn

; ---- load: operand[0] is a variable NUMBER, read indirectly; the
; value read is stored via this instruction's own store_variable ----
zds_load:
            mov     rf, zdisp_operand+1
            ldn     rf                  ; d = variable number
            call    zvar_read_indirect  ; rf = value, df=err
            lbdf    zds_error

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- not: bitwise complement, store ----
zds_not:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0]

            ghi     r9
            not
            phi     r9
            glo     r9
            not
            plo     r9                  ; r9 = ~operand[0]

            mov     rf, r9
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zds_error:
            stc
            rtn
            endp

; zdisp_store_and_branch_nonzero (internal): D = an object number (0-
; 255, zero-extended into the store below; set immediately before the
; call -- nothing else may run between the zobj_get_sibling/
; zobj_get_child call that produced it and this one, since nothing
; else is guaranteed to leave d alone). Stores it into the current
; instruction's own store_variable, then branches if it's nonzero.
; Shared by get_sibling/get_child, whose Z-machine semantics are
; identical from this point on. DF=1 propagates a zvar_write failure.
            proc    zdisp_store_and_branch_nonzero
            plo     ra                  ; ra.0 = the value
            mov     r8, zdisp_value
            ldi     0
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zdisp_value = 0:value --
                                        ; stashed in memory, since
                                        ; zvar_write's own clobber
                                        ; footprint is wide enough to
                                        ; reach any register

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = zdisp_value, reloaded
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            lbdf    zdsb_fail

            mov     r8, zdisp_value
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = zdisp_value, reloaded
                                        ; again fresh (zvar_write may
                                        ; have clobbered anything)
            glo     r9
            lbnz    zdsb_nonzero
            ghi     r9
            lbnz    zdsb_nonzero
            ldi     0
            lbr     zdsb_branch
zdsb_nonzero:
            ldi     1
zdsb_branch:
            call    zdisp_branch
            rtn

zdsb_fail:
            stc
            rtn
            endp

; zdisp_slt (internal): RD = a, RF = b, both signed 16-bit (set
; immediately before the call). Returns D = 1 if a < b, else D = 0 --
; ready to feed straight into zdisp_branch's own D=condition
; parameter. Flips both operands' sign bits (biasing signed order to
; match the 1802's own unsigned SM/SMB order -- see this project's own
; DF/borrow convention note) and does a plain unsigned sub16, then
; treats a "no borrow but nonzero" result as strictly less-than
; (borrow alone would mean b < a; a zero result means a == b, neither
; of which is "a < b").
            proc    zdisp_slt
            mov     r8, rd
            ghi     r8
            xri     $80
            phi     r8
            glo     rd
            plo     r8                  ; r8 = a, sign bit flipped

            mov     r9, rf
            ghi     r9
            xri     $80
            phi     r9
            glo     rf
            plo     r9                  ; r9 = b, sign bit flipped

            mov     rb, r9
            sub16   rb, r8              ; rb = biased_b - biased_a;
                                        ; DF=1 (no borrow) means
                                        ; biased_b >= biased_a, i.e.
                                        ; a <= b
            lbnf    zslt_false          ; DF=0: b < a, so a is not < b

            glo     rb
            lbnz    zslt_true
            ghi     rb
            lbnz    zslt_true           ; rb != 0: a < b strictly
zslt_false:
            ldi     0
            rtn
zslt_true:
            ldi     1
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

; zdisp_print_inline (internal): decodes and emits the CURRENT
; instruction's own inline packed z-text (immediately following its
; 1-byte opcode, spanning the rest of instr.length -- decode already
; measured this exactly for a has_text opcode, the same way it does
; for instr.length itself). zdec_decode's own output is already NUL-
; terminated, so the whole string goes to zdisp_emit_string in one
; call -- no need to walk it a character at a time the way host's own
; per-character emit callback does; that shape doesn't exist on this
; side, and doesn't need to. DF=1 on a z-text decode failure (an
; unsupported abbreviation z-char, matching zdec_decode's own).
            proc    zdisp_print_inline
            mov     r8, zdisp_instr+ZDI_ADDR
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = addr
            add16   r9, 1               ; r9 = addr+1 (skip the
                                        ; opcode byte) -- still a GUEST
                                        ; address at this point

            mov     r8, zmbase
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = zmbase (the real host
                                        ; address the guest's own
                                        ; address 0 maps to)
            add16   r9, ra              ; r9 = the real host address of
                                        ; the packed text -- zdec_decode
                                        ; (unlike zmread/zde_read_byte)
                                        ; reads real memory directly,
                                        ; with no guest-address concept
                                        ; of its own, so this
                                        ; translation is this call
                                        ; site's own job. Safe to do
                                        ; without zmread's own bounds
                                        ; check: decode_instruction's
                                        ; has_text scan already walked
                                        ; every one of these bytes
                                        ; through zmread to measure
                                        ; instr.length in the first
                                        ; place, so they're already
                                        ; known resident
            mov     rd, r9              ; rd = packed text address

            mov     r8, zdisp_instr+ZDI_LENGTH
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = length
            sub16   ra, 1               ; ra = length-1 (packed byte
                                        ; count)
            mov     rc, ra

            mov     rf, zdisp_text_buf
            call    zdec_decode         ; decodes into zdisp_text_buf,
                                        ; NUL-terminated
            lbdf    zdpi_fail

            mov     rf, zdisp_text_buf
            call    zdisp_emit_string
            clc
            rtn

zdpi_fail:
            stc
            rtn
            endp

            proc    _zdispatch_data
zdisp_pc:            dw      0
zdisp_quit:           db      0
zdisp_i:              db      0
zdisp_next_pc:         dw      0
zdisp_value:            dw      0
zdisp_value2:           dw      0       ; second scratch word, for
                                        ; opcodes that need two 16-bit
                                        ; values to survive a zvar_*
                                        ; call (dec_chk/inc_chk's own
                                        ; updated value + threshold)
zdisp_routine_addr:      dw      0
zdisp_local_count:        db      0
zdisp_instr:               ds      ZDI_SIZE
zdisp_operand:              ds      8       ; 4 resolved operand words
zdisp_locals:                ds      30      ; up to 15 locals
zdisp_text_buf:               ds      512     ; decoded print-family
                                              ; text -- generous for
                                              ; any V3 game string,
                                              ; not defensively bounds-
                                              ; checked against zdec_
                                              ; decode's own output
                                              ; (matches this project's
                                              ; established "trust the
                                              ; input" boundary)
zdisp_newline_buf:             db      10, 0   ; a constant 2-byte
                                              ; NUL-terminated "\n",
                                              ; reused by both
                                              ; print_ret and new_line

                public  zdisp_pc
                public  zdisp_quit
                public  zdisp_i
                public  zdisp_next_pc
                public  zdisp_value
                public  zdisp_value2
                public  zdisp_routine_addr
                public  zdisp_local_count
                public  zdisp_instr
                public  zdisp_operand
                public  zdisp_locals
                public  zdisp_text_buf
                public  zdisp_newline_buf
            endp
