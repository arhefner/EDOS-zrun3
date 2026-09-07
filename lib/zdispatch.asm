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
            extrn   zmwrite
            extrn   zmwrite16
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
            extrn   zobj_short_name
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
            extrn   zprop_put
            extrn   ym_fmt_uint32
            extrn   zparse_init
            extrn   zparse_tokenize
            extrn   zdi_dict_addr
            extrn   zdi_dict_guest
            extrn   zdisp_read_line
            extrn   zstatus_draw
            extrn   zdisp_save_game
            extrn   zdisp_restore_game

            extrn   zdisp_branch
            extrn   zdisp_return
            extrn   zdisp_do_call
            extrn   zdisp_print_inline
            extrn   zdisp_store_and_branch_nonzero
            extrn   zdisp_slt
            extrn   zwide_add_signed
            extrn   zdisp_print_at
            extrn   zrand_step
            extrn   zrand_shl32
            extrn   zrand_shr32
            extrn   zrand_stash
            extrn   zrand_xor_tmp
            extrn   zdisp_umod16
            extrn   zdisp_udivmod16
            extrn   zdisp_sdivmod16
            extrn   zrand_state
            extrn   zrand_tmp

            extrn   zdisp_pc
            extrn   zdisp_pc_bank
            extrn   zdisp_quit
            extrn   zdisp_i
            extrn   zdisp_next_pc
            extrn   zdisp_next_pc_bank
            extrn   zdisp_value
            extrn   zdisp_value2
            extrn   zdisp_routine_addr
            extrn   zdisp_routine_addr_hi
            extrn   zdisp_local_count
            extrn   zdisp_call_scratch
            extrn   zm_bank
            extrn   zdisp_instr
            extrn   zdisp_operand
            extrn   zdisp_locals
            extrn   zdisp_text_buf
            extrn   zdisp_packed_buf
            extrn   zmread_bytes
            extrn   zdisp_newline_buf
            extrn   zdisp_char_buf
            extrn   zdisp_num_buf

; zdisp_step: no arguments (uses zdisp_pc). Returns DF=1 for a decode
; error or an opcode this slice doesn't recognize yet.
            proc    zdisp_step
            ; BUG FIX: both pointers are set up FIRST and the byte
            ; loaded LAST. "mov r9, zm_bank" ends in "ldi <zm_bank's
            ; own low address byte> / plo r9" and so CLOBBERS D
            ; (toolchain gotcha #2) -- with it sitting between the ldn
            ; and the str, zm_bank was set to the LOW BYTE OF ITS OWN
            ; ADDRESS rather than to zdisp_pc_bank. zmread then handed
            ; that byte to zcread as the 32-bit offset's HIGH word, so
            ; the very first opcode fetch seeked to <garbage>:4F05 --
            ; the long-parked "K_FILE_SEEK target's high word is
            ; corrupted for >64K story files" bug. It looked
            ; layout-sensitive (any edit changed the symptom) because
            ; the bogus value IS an address low byte, and it never
            ; reproduced in diag/zseekdiag_main.asm because that
            ; program's own two zm_bank writes both already load the
            ; pointer before the byte.
            mov     r9, zm_bank
            mov     r8, zdisp_pc_bank
            ldn     r8
            str     r9                  ; zm_bank = zdisp_pc_bank, so
                                        ; this instruction's own fetch
                                        ; (through zmread, inside
                                        ; zdecode_instruction) lands in
                                        ; the right bank for a story
                                        ; file over 64K

            mov     r8, zdisp_pc
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = current pc (low word)

            mov     rf, zdisp_instr
            call    zdecode_instruction
            lbdf    zds_error

            mov     r9, zm_bank         ; reset zm_bank to 0
            ldi     0                   ; immediately -- every OTHER
            str     r9                  ; zmread call for the rest of
                                        ; this opcode's own execution
                                        ; (globals, properties, operand
                                        ; reads) is always within the
                                        ; first 64K and assumes bank 0

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
            add16   r8, r9              ; r8 = next_pc (low word,
                                        ; wrapped); DF=1 iff this
                                        ; overflowed past 0xffff (ADD's
                                        ; own carry-out, unrelated to
                                        ; SM/SMB's inverted sense)

            mov     rf, zdisp_pc_bank
            ldn     rf                  ; d = the current bank
            lbnf    zds_pc_no_carry     ; DF=0: no overflow, bank
                                        ; unchanged
            adi     1                   ; DF=1: this instruction's own
                                        ; bytes ended exactly at a 64K
                                        ; boundary -- carry into the
                                        ; next bank
zds_pc_no_carry:
            plo     r9                  ; r9.0 = next_pc's own bank

            mov     rf, zdisp_next_pc
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf
            mov     rf, zdisp_next_pc_bank
            glo     r9
            str     rf

            mov     rf, zdisp_pc        ; commit the default fallthrough
            ghi     r8                  ; now -- every opcode handler
            str     rf                  ; below that branches/calls/
            inc     rf                  ; returns overrides this later
            glo     r8                  ; in the same zdisp_step call
            str     rf
            mov     rf, zdisp_pc_bank
            glo     r9
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
            xri     15
            lbz     zds_loadw
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     16
            lbz     zds_loadb
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
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     22
            lbz     zds_mul
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     23
            lbz     zds_div
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     24
            lbz     zds_mod
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
            xri     7
            lbz     zds_print_addr
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     9
            lbz     zds_remove_obj
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     10
            lbz     zds_print_obj
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
            xri     13
            lbz     zds_print_paddr
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
            xri     5
            lbz     zds_save
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     6
            lbz     zds_restore
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     7
            lbz     zds_restart
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     8
            lbz     zds_ret_popped
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     9
            lbz     zds_pop
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
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     1
            lbz     zds_storew
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     2
            lbz     zds_storeb
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     3
            lbz     zds_put_prop
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     4
            lbz     zds_sread
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     5
            lbz     zds_print_char
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     6
            lbz     zds_print_num
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     7
            lbz     zds_random
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     8
            lbz     zds_push
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     9
            lbz     zds_pull
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     19
            lbz     zds_output_stream
            mov     rf, zdisp_instr+ZDI_OPCODE
            ldn     rf
            xri     20
            lbz     zds_input_stream
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

; ---- mul: 16x16->16 unsigned shift-add multiply, truncated to the
; low 16 bits. Correct for signed Z-machine operands too: two's-
; complement multiplication truncated to the same width is bit-
; identical whether the inputs are read as signed or unsigned, so no
; sign handling is needed here (unlike div/mod below, whose quotient
; and remainder magnitudes are NOT truncation-invariant) ----
zds_mul:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (multiplier,
                                        ; consumed bit-by-bit below)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (multiplicand,
                                        ; doubled each iteration)

            ldi     0
            phi     r8
            plo     r8                  ; r8 = product accumulator
            ldi     16
            plo     rb                  ; rb.0 = iteration count

zmul_loop:
            glo     rb
            lbz     zmul_done

            glo     r9
            ani     1
            lbz     zmul_no_add
            add16   r8, ra              ; product += multiplicand

zmul_no_add:
            shl16   ra                  ; multiplicand <<= 1 (bits
                                        ; shifted past bit15 are
                                        ; discarded, same as the
                                        ; product's own add16
                                        ; wraparound -- only the low 16
                                        ; bits are ever wanted)
            shr16   r9                  ; multiplier >>= 1, unsigned
                                        ; (only its bits are tested,
                                        ; never its value)

            dec     rb
            lbr     zmul_loop

zmul_done:
            mov     rf, r8
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- div / mod: signed 16-bit, truncating toward zero, remainder
; takes the dividend's sign (matching the Z-machine spec and C's own
; convention) -- both delegate to zdisp_sdivmod16, which returns both
; results from a single division so the sign bookkeeping is written
; once rather than twice. DF=1 (divide by zero) routes to zds_error
; exactly like every other opcode failure here ----
zds_div:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (dividend)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (divisor)

            mov     rd, r9
            mov     rf, ra
            call    zdisp_sdivmod16     ; rd = quotient, rc =
                                        ; remainder, df=1 on /0
            lbdf    zds_error

            mov     rf, rd
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zds_mod:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (dividend)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (divisor)

            mov     rd, r9
            mov     rf, ra
            call    zdisp_sdivmod16     ; rd = quotient, rc =
                                        ; remainder, df=1 on /0
            lbdf    zds_error

            mov     rf, rc
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
            add16   r8, r9              ; r8 = after (== zdisp_pc's own
                                        ; current value, already
                                        ; committed by zdisp_step's own
                                        ; preamble -- zdisp_pc_bank
                                        ; there already reflects this
                                        ; sum's own bank, reused
                                        ; directly below rather than
                                        ; recomputed)

            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (signed)
            sub16   r9, 2               ; r9 = operand[0] - 2 (a small
                                        ; signed adjustment, always
                                        ; safely within 16-bit signed
                                        ; range on its own)

            mov     rf, zdisp_pc_bank
            ldn     rf
            plo     rd
            ldi     0
            phi     rd                  ; rd = 0:zdisp_pc_bank ("after"
                                        ; address's own bank) -- BUG FIX:
                                        ; the phi/plo were the wrong way
                                        ; round, making RD $0100 rather
                                        ; than $0001 for bank 1, so
                                        ; zwide_add_signed's own result
                                        ; bank came back with its real
                                        ; value in the high byte and
                                        ; "glo rd" then stored 0. Every
                                        ; taken branch and every jump
                                        ; inside a routine past 64K
                                        ; silently dropped back to bank 0
            mov     rf, r8              ; rf = after's low word
            mov     rc, r9              ; rc = signed delta
            call    zwide_add_signed    ; rd:rf = target bank:offset

            mov     r8, zdisp_pc
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_pc = target offset
            mov     r8, zdisp_pc_bank
            glo     rd
            str     r8                  ; zdisp_pc_bank = target bank
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

; ---- storew / storeb: operand[0]=array base (guest), operand[1]=
; index, operand[2]=value -- write the word/byte at array + 2*index /
; array + index; no store, no branch ----
zds_storew:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (array base)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (word index)
            mov     rf, zdisp_operand+4
            lda     rf
            phi     rb
            ldn     rf
            plo     rb                  ; rb = operand[2] (value)

            shl16   ra                  ; ra = index * 2
            add16   r9, ra              ; r9 = array + 2*index

            mov     rd, r9
            mov     rf, rb
            call    zmwrite16
            rtn

zds_storeb:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (array base)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (byte index)
            mov     rf, zdisp_operand+4
            lda     rf
            phi     rb
            ldn     rf
            plo     rb                  ; rb = operand[2] (value)

            add16   r9, ra              ; r9 = array + index

            mov     rd, r9
            mov     rf, rb
            call    zmwrite
            rtn

; ---- put_prop: operand[0]=object, operand[1]=property, operand[2]=
; value; no store, no branch ----
zds_put_prop:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (object)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (property)
            mov     rf, zdisp_operand+4
            lda     rf
            phi     rb
            ldn     rf
            plo     rb                  ; rb = operand[2] (value)

            mov     rd, r9
            mov     rf, rb              ; rf = value -- set before the
                                        ; D-setting glo below (a
                                        ; register-to-register mov
                                        ; clobbers D too)
            glo     ra                  ; d = property, last before
                                        ; the call
            call    zprop_put
            rtn

; ---- print_char: emit operand[0]'s low byte as a single character ----
zds_print_char:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (character)

            mov     r8, zdisp_char_buf
            glo     r9
            str     r8
            inc     r8
            ldi     0
            str     r8                  ; zdisp_char_buf = char, NUL

            mov     rf, zdisp_char_buf
            call    zdisp_emit_string
            clc
            rtn

; ---- print_num: emit operand[0] as a signed decimal string, via
; lib/ymodem.asm's own established ym_fmt_uint32 (32-bit unsigned,
; RD:R8 = value, RF = destination buffer) -- a negative operand is
; negated to its magnitude first, with '-' written directly into
; zdisp_num_buf ahead of where ym_fmt_uint32's own digits land, so
; the whole thing goes to zdisp_emit_string in one call ----
zds_print_num:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (signed)

            mov     rb, zdisp_num_buf   ; rb = ym_fmt_uint32's own
                                        ; destination cursor
            ghi     r9
            ani     $80
            lbz     zpn_positive

            ldi     '-'
            str     rb
            inc     rb

            ghi     r9
            not
            phi     r9
            glo     r9
            not
            plo     r9
            add16   r9, 1               ; r9 = magnitude (negate)

zpn_positive:
            mov     r8, r9              ; r8 = value's low word
            ldi     0
            plo     rd
            phi     rd                  ; rd = 0 (value's high word --
                                        ; our magnitude never exceeds
                                        ; 32768, always fits in r8 alone)
            mov     rf, rb              ; rf = destination for
                                        ; ym_fmt_uint32's own digits
            call    ym_fmt_uint32

            mov     rf, zdisp_num_buf
            call    zdisp_emit_string
            clc
            rtn

; ---- push: operand[0] pushed onto the eval stack (variable 0's own
; "pushes" semantics via zvar_write); no store, no branch ----
zds_push:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0]

            mov     rf, r9
            ldi     0
            call    zvar_write
            rtn

; ---- pull: operand[0] is a variable NUMBER (re-read fresh from
; zdisp_operand+1 after the pop below, same reasoning as dec_chk/
; inc_chk/inc/dec above), written indirectly with the popped value ----
zds_pull:
            ldi     0
            call    zvar_read           ; rf = popped value, df=err
            lbdf    zds_error

            mov     r8, zdisp_value
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value = popped value

            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = popped value, reloaded
                                        ; fresh
            mov     r8, zdisp_operand+1
            ldn     r8                  ; d = variable number
            call    zvar_write_indirect
            rtn

; ---- random: operand[0] > 0 draws 1..operand[0] via zrand_step +
; zdisp_umod16; operand[0] == 0 reseeds from zdisp_pc (no true entropy
; source without a kernel hook -- see zrand_step's own header); < 0
; reseeds deterministically from the magnitude, matching host's own
; vm_random. Seeding calls always store/return 0. ----
zds_random:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (signed range)

            glo     r9
            lbnz    zdr_check_sign
            ghi     r9
            lbnz    zdr_check_sign
            lbr     zdr_reseed_zero

zdr_check_sign:
            ghi     r9
            ani     $80
            lbnz    zdr_reseed_negative
            lbr     zdr_draw

zdr_reseed_zero:
            mov     r8, zdisp_pc
            lda     r8
            phi     ra
            ldn     r8
            ori     1
            plo     ra                  ; ra = zdisp_pc | 1 (guaranteed
                                        ; odd, so nonzero)

            mov     r9, zrand_state
            ldi     $9e
            str     r9
            inc     r9
            ldi     $37
            str     r9                  ; hi word = fixed constant
            inc     r9
            ghi     ra
            str     r9
            inc     r9
            glo     ra
            str     r9                  ; lo word = zdisp_pc | 1
            lbr     zdr_store_zero

zdr_reseed_negative:
            ghi     r9
            not
            phi     r9
            glo     r9
            not
            plo     r9
            add16   r9, 1               ; r9 = magnitude (negate)
            glo     r9
            ori     1
            plo     r9                  ; ensure odd/nonzero

            mov     ra, zrand_state
            ldi     0
            str     ra
            inc     ra
            ldi     0
            str     ra                  ; hi word = 0
            inc     ra
            ghi     r9
            str     ra
            inc     ra
            glo     r9
            str     ra                  ; lo word = magnitude | 1

zdr_store_zero:
            mov     rf, 0
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zdr_draw:
            mov     r8, zdisp_value
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zdisp_value = range (stashed
                                        ; across zrand_step, which
                                        ; clobbers everything)

            call    zrand_step          ; rd:r8 = new 32-bit state

            mov     rd, r8              ; rd = low 16 bits of the new
                                        ; state (the draw source -- see
                                        ; zrand_step's own header on
                                        ; why only the low word is
                                        ; used, unlike host's exact
                                        ; 32-bit modulo)
            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = range, reloaded fresh
            call    zdisp_umod16        ; rd = draw mod range
            add16   rd, 1               ; rd = 1..range

            mov     rf, rd
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

; ---- sread: reads a line into the text buffer at operand[0] (byte 0
; = max length, characters start at byte 1, V3 has no length byte),
; lowercased and NUL-terminated by zdisp_read_line, then tokenizes it
; into the parse buffer at operand[1] via zparse_init + zparse_tokenize.
; zdict_init is NOT called here (an earlier version re-derived the
; dictionary's real address from zmbase + the header's own dictionary
; field on every single sread call, the same story-header lookup
; zmread16(8) below still does for a different reason) -- the
; dictionary normally lives in STATIC memory, past the resident
; dynamic-memory region a real story loader allocates (see lib/
; zload.asm's own header comment for why it gets its own dedicated
; buffer instead of sharing zmbase's), so "zmbase + dictionary offset"
; only ever pointed at the right bytes when a diag's own test data
; happened to place the dictionary inside its single resident test
; buffer (see diag/zdispatchdiag.asm's check 9, which does exactly
; that and now calls zdict_init directly in its own setup instead).
; The loader calls zdict_init exactly once, at load time; zdict_lookup/
; zparse_tokenize already work purely off the zdi_dict_addr global it
; sets, so nothing here needs to touch it again. Both zdict.asm and
; zparse.asm, like zobj.asm/zprop.asm, operate entirely on REAL
; addresses with no zmbase translation of their own (confirmed against
; diag/zdictdiag.asm's own check 6, which asserts zdict_find_word
; returns zt_dict+12 -- a REAL linked address, not a story-relative
; one), so the parse buffer's own entry_addr fields (as written by
; zparse_tokenize) are translated real->guest here, at the dispatch
; boundary, exactly like get_prop_addr's own translation. No store, no
; branch (V3's sread has neither). ----
zds_sread:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (text
                                        ; buffer, guest)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (parse
                                        ; buffer, guest)

            mov     r8, zmbase
            lda     r8
            phi     rb
            ldn     r8
            plo     rb                  ; rb = zmbase
            add16   r9, rb              ; r9 = real text buffer addr
            add16   ra, rb              ; ra = real parse buffer addr

            mov     r8, zdisp_value
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zdisp_value = real text
                                        ; buffer addr
            mov     r8, zdisp_value2
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zdisp_value2 = real parse
                                        ; buffer addr

            call    zstatus_draw        ; per the Z-machine standard,
                                        ; the status line must be
                                        ; redisplayed whenever the game
                                        ; reads a line of input -- df
                                        ; ignored, a status-line hiccup
                                        ; shouldn't abort the game

            mov     r8, zdisp_value
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = real text buffer addr,
                                        ; reloaded fresh (zstatus_draw
                                        ; may have clobbered it)
            mov     rd, r9
            call    zdisp_read_line     ; df=1 on abort/error
            lbdf    zds_error

; measure the read length by scanning for the NUL zdisp_read_line
; left after the character data
            mov     r8, zdisp_value
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            add16   rf, 1               ; rf = real addr of char data
                                        ; (buf+1)
            mov     r9, rf              ; r9 = char data start --
                                        ; survives the scan below
                                        ; (nothing in it calls anything)
            ldi     0
            plo     rc
            phi     rc                  ; rc = 0 (length counter)
zdsr_count:
            ldn     rf
            lbz     zdsr_have_len
            inc     rf
            inc     rc
            lbr     zdsr_count
zdsr_have_len:
                                        ; rc.0 = read length (always
                                        ; < 256: max_length is a byte)

            mov     rd, r9              ; rd = char data start
                                        ; (zparse_init's text address)
            mov     r8, zdisp_value2
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = real parse buffer addr
            ldi     1
            phi     rc                  ; rc.hi = text_offset = 1
                                        ; (skips the 1-byte max-length
                                        ; header, matching host's own
                                        ; sread call); rc.lo = length,
                                        ; untouched
            call    zparse_init
            call    zparse_tokenize     ; df=1 only if a word is
                                        ; unencodable
            lbdf    zds_error

; translate each parsed word's entry_addr field from real to guest --
; word_count lives at parse_addr+1, entries start at parse_addr+2,
; 4 bytes each (entry_addr hi/lo, length, position).
;
; The mapping is the DICTIONARY's own (real -> zdi_dict_addr-relative
; offset -> zdi_dict_guest), not zmbase's: a V3 dictionary lives in
; static memory and zload_story gives it a dedicated resident buffer
; with no zmbase relationship at all. This used "real - zmbase", which
; only coincides with the right answer when the dictionary sits inside
; the dynamic buffer -- true of the diagnostics' fake images, false for
; every real story file, so the game got garbage entry addresses and
; rejected every command it could otherwise parse.
            mov     r8, zdisp_value2
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = real parse buffer addr
            inc     rf
            ldn     rf                  ; d = word_count
            plo     rb
            ldi     0
            phi     rb                  ; rb = 0:word_count

            mov     r8, zdisp_value2
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            add16   r9, 2               ; r9 = real addr of entry[0]

            mov     r8, zdi_dict_addr
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = the dictionary buffer's
                                        ; own real base
            mov     r8, zdi_dict_guest
            lda     r8
            phi     r7
            ldn     r8
            plo     r7                  ; r7 = that dictionary's guest
                                        ; address (nothing in the loop
                                        ; below calls anything, so both
                                        ; survive it)

zdsr_xlate_loop:
            glo     rb
            lbnz    zdsr_xlate_have
            ghi     rb
            lbnz    zdsr_xlate_have
            clc
            rtn                         ; word_count == 0: done

zdsr_xlate_have:
            mov     rf, r9
            lda     rf
            phi     rc
            ldn     rf
            plo     rc                  ; rc = this entry's addr field
                                        ; (real, or 0 if absent)

            glo     rc
            lbnz    zdsr_xlate_do
            ghi     rc
            lbz     zdsr_xlate_skip     ; absent (0): don't translate

zdsr_xlate_do:
            sub16   rc, ra              ; rc = offset into the buffer
            add16   rc, r7              ; rc = the guest address
            mov     rf, r9
            ghi     rc
            str     rf
            inc     rf
            glo     rc
            str     rf

zdsr_xlate_skip:
            add16   r9, 4               ; r9 = next entry
            dec     rb
            lbr     zdsr_xlate_loop

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

; ---- loadw / loadb: operand[0]=array base (guest), operand[1]=index
; -> store the word/byte at array + 2*index / array + index ----
zds_loadw:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (array base)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (word index)

            shl16   ra                  ; ra = index * 2
            add16   r9, ra              ; r9 = array + 2*index

            mov     rd, r9
            call    zmread16            ; rf = value, df=err
            lbdf    zds_error

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
            rtn

zds_loadb:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (array base)
            mov     rf, zdisp_operand+2
            lda     rf
            phi     ra
            ldn     rf
            plo     ra                  ; ra = operand[1] (byte index)

            add16   r9, ra              ; r9 = array + index

            mov     rd, r9
            call    zmread              ; d = byte, df=err
            lbdf    zds_error

            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:byte (zero-extended)
            mov     rf, rc

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            call    zvar_write
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

; ---- print_addr: operand[0] is a guest/story address of packed
; z-text (not this instruction's own inline text) -- decode+emit via
; zdisp_print_at, which takes a GUEST address (not a real one): the
; text this points at is ordinary story-file prose, almost always
; static or high memory, so it must go through zmread's cache-aware
; path, not zmbase-relative pointer arithmetic that only works for
; resident bytes ----
zds_print_addr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (guest addr,
                                        ; always plain 16-bit -- a
                                        ; direct byte address operand,
                                        ; never packed, so it can never
                                        ; exceed 65535 on its own)

            mov     rd, r9
            mov     ra, 0
            call    zdisp_print_at
            rtn

; ---- print_paddr: operand[0] is a V3 packed address (guest address
; = operand[0]*2) of packed z-text. The doubling can legitimately
; carry into a 17th bit for a story file over 64K (most of the V3
; sample library), which a plain shl16 would silently discard -- shl/
; shlc across both bytes instead, same multi-byte shift-chain idiom
; used throughout this project, so the bit that falls off bit15 (DF
; after the chain) becomes the address's own high word rather than
; vanishing. ----
zds_print_paddr:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (packed addr)

            glo     r9
            shl
            plo     r9
            ghi     r9
            shlc
            phi     r9                  ; r9 = operand[0]*2, wrapped to
                                        ; 16 bits; DF = the 17th bit
            ldi     0
            plo     ra
            lbnf    zpp_no_carry
            ldi     1
            plo     ra
zpp_no_carry:
            ldi     0
            phi     ra                  ; ra = address's high word

            mov     rd, r9
            call    zdisp_print_at
            rtn

; ---- print_obj: operand[0] is an object number -- decode+emit its
; own short name, using zobj_short_name's own exact length rather
; than zdisp_print_at's generous fixed one (available for free here,
; unlike print_addr/print_paddr, which have no prior measurement) ----
zds_print_obj:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (object)

            mov     rd, r9
            call    zobj_short_name     ; rf = real text addr, rc =
                                        ; length (bytes)
            mov     rd, rf
            mov     rf, zdisp_text_buf
            call    zdec_decode
            lbdf    zds_error

            mov     rf, zdisp_text_buf
            call    zdisp_emit_string
            clc                         ; BUG FIX: this was the one
                                        ; zdisp_emit_string call site in
                                        ; this file that returned without
                                        ; clearing DF, so it handed the
                                        ; caller whatever K_MSG happened
                                        ; to leave -- and on real ELF-DOS
                                        ; hardware that is DF=1, so
                                        ; print_obj printed its object's
                                        ; name correctly and then reported
                                        ; a bogus opcode error. Invisible
                                        ; under Run/02 (its emulated K_MSG
                                        ; returns DF=0) and invisible to
                                        ; diag/zdispatchdiag.asm (its own
                                        ; zdisp_emit_string double already
                                        ; ended in clc). zdisp_emit_string
                                        ; itself now guarantees DF=0 too;
                                        ; this stays for symmetry with
                                        ; every other call site here.
            rtn

; ---- save: per the V1-3 branch encoding, the branch is committed
; unconditionally FIRST (matching host/dispatch.c's own do_branch(
; instr,1) call -- there's no other way to compute the branch target
; without duplicating zdisp_branch's own logic), then undone (zdisp_pc
; reset to the fallthrough zdisp_step already committed before
; dispatch) only if zdisp_save_game actually fails. Delegates the
; actual file I/O to zdisp_save_game, a narrow platform hook (matching
; zdisp_emit_string/zdisp_read_line's own precedent -- the core never
; touches K_FILE_* directly). If the branch offset is 0 or 1 (return
; false/true instead of a jump), zdisp_branch already delegated to
; zdisp_return by the time save's own failure path would try to
; "undo" it -- host has this same limitation (do_branch's own
; side effect can't be cleanly reverted either), not fixed here. ----
zds_save:
            mov     r8, zdisp_pc
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = fallthrough pc (already
                                        ; committed by zdisp_step)

            mov     r8, zdisp_value
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zdisp_value = fallthrough pc
                                        ; -- stashed in memory, since
                                        ; zdisp_branch uses R7 for its
                                        ; own condition parameter

            mov     r9, zdisp_value2    ; destination pointer FIRST,
            mov     r8, zdisp_pc_bank   ; byte LAST -- mov clobbers d
            ldn     r8                  ; (toolchain gotcha #2); this
            str     r9                  ; used to stash zdisp_value2's
                                        ; own low address byte instead
                                        ; of the bank. zdisp_value2 =
                                        ; fallthrough pc's own bank -- a
                                        ; taken branch below could change
                                        ; it, and the undo path needs it
                                        ; back exactly as it was

            ldi     1
            call    zdisp_branch        ; unconditionally commits the
                                        ; branch target into zdisp_pc

            call    zdisp_save_game     ; df=1 on failure
            lbnf    zds_save_done

            mov     r8, zdisp_value
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = fallthrough pc, reloaded
            mov     r8, zdisp_pc
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; undo: zdisp_pc = fallthrough
            mov     r9, zdisp_pc_bank   ; pointer first, byte last --
            mov     r8, zdisp_value2    ; same D-clobber fix as the
            ldn     r8                  ; stash above
            str     r9                  ; undo: zdisp_pc_bank =
                                        ; fallthrough's own bank

zds_save_done:
            clc
            rtn

; ---- restore: "the branch is never actually made" -- on success,
; zdisp_restore_game overwrites zdisp_pc wholesale as part of the
; restored state; on failure, zdisp_pc is left exactly as zdisp_step's
; own default fallthrough already set it, which IS "falls through
; normally" ----
zds_restore:
            call    zdisp_restore_game  ; df=1 on failure
            clc
            rtn

; ---- restart: no pristine-dynamic-memory source exists anywhere in
; this project yet (no story-loader/interpreter-frontend has been
; built), so this is an honest "unsupported" stub -- matches host's
; own documented behavior when ctx->restart is left unconfigured
; (a decode-recognized but unsupported opcode, not a silent no-op) ----
zds_restart:
            stc
            rtn

; ---- ret_popped / pop: pop the eval stack (variable 0's own "pops"
; semantics via zvar_read) -- ret_popped returns the popped value,
; pop just discards it ----
zds_ret_popped:
            ldi     0
            call    zvar_read           ; rf = popped value, df=err
            lbdf    zds_error
            call    zdisp_return
            rtn

zds_pop:
            ldi     0
            call    zvar_read           ; rf = popped value (discarded),
                                        ; df=err
            rtn

; ---- output_stream: only streams other than 3 are supported (host's
; own model doesn't have a separate transcript sink for 2/4 either;
; here 3's memory-table redirect is additionally declined, since it
; needs per-character counting that zdisp_emit_string's own batched-
; string interface doesn't fit) -- +-3 returns DF=1 rather than
; silently doing nothing; anything else (including -3, tearing down a
; redirect that was never active) is accepted as a no-op ----
zds_output_stream:
            mov     rf, zdisp_operand
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = operand[0] (signed
                                        ; stream number)

            ghi     r9
            lbnz    zdos_check_neg3     ; hi != 0: can't be +3
            glo     r9
            xri     3
            lbz     zdos_unsupported
            lbr     zdos_ok

zdos_check_neg3:
            ghi     r9
            xri     $ff
            lbnz    zdos_ok             ; hi != 0xff: can't be -3
            glo     r9
            xri     $fd
            lbz     zdos_unsupported

zdos_ok:
            clc
            rtn

zdos_unsupported:
            stc
            rtn

; ---- input_stream: no-op (matches host -- only one input source
; exists, so any request is silently accepted) ----
zds_input_stream:
            clc
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

; zwide_add_signed (internal): RD = bank (high word), RF = offset (low
; word), RC = signed 16-bit delta (all set immediately before the
; call). Returns RD:RF = the updated bank:offset, carrying into (or
; borrowing out of) the bank when the offset arithmetic wraps past a
; 64K boundary. Needed by any bank:offset address computation that
; adds a SIGNED delta -- branch/jump targets -- unlike zmread_bytes'
; own always-forward, unsigned "+1 per byte" advance, which never
; needs this. Uses this project's own established SM/SMB convention
; (DF=1 means NO borrow) for the negative-delta case; ADD's own DF
; (unrelated to SM/SMB -- DF=1 here means a carry DID occur) for the
; positive case.
            proc    zwide_add_signed
            ghi     rc
            ani     $80
            lbnz    zwas_negative

; delta >= 0: plain add, carry into the bank on overflow
            add16   rf, rc
            lbnf    zwas_done           ; DF=0: no carry
            add16   rd, 1
zwas_done:
            rtn

zwas_negative:
; delta < 0: subtract its magnitude, borrowing out of the bank if the
; offset itself underflows
            ghi     rc
            not
            phi     rc
            glo     rc
            not
            plo     rc
            add16   rc, 1               ; rc = |delta|

            sub16   rf, rc              ; DF=1 (no borrow): offset >=
                                        ; magnitude, bank unchanged;
                                        ; DF=0 (borrow): offset itself
                                        ; wrapped, bank -= 1
            lbdf    zwas_done
            sub16   rd, 1
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
            add16   r9, ra              ; r9 = after (== zdisp_pc's own
                                        ; current value, already
                                        ; committed by zdisp_step's own
                                        ; preamble -- zdisp_pc_bank
                                        ; there already reflects this
                                        ; sum's own bank, reused
                                        ; directly below rather than
                                        ; recomputed)
            sub16   r8, 2               ; r8 = branch_offset - 2 (a
                                        ; small signed adjustment,
                                        ; always safely within 16-bit
                                        ; signed range on its own)

            mov     rf, zdisp_pc_bank
            ldn     rf
            plo     rd
            ldi     0
            phi     rd                  ; rd = 0:zdisp_pc_bank ("after"
                                        ; address's own bank) -- BUG FIX:
                                        ; the phi/plo were the wrong way
                                        ; round, making RD $0100 rather
                                        ; than $0001 for bank 1, so
                                        ; zwide_add_signed's own result
                                        ; bank came back with its real
                                        ; value in the high byte and
                                        ; "glo rd" then stored 0. Every
                                        ; taken branch and every jump
                                        ; inside a routine past 64K
                                        ; silently dropped back to bank 0
            mov     rf, r9              ; rf = after's low word
            mov     rc, r8              ; rc = signed delta
            call    zwide_add_signed    ; rd:rf = target bank:offset

            mov     r9, zdisp_pc
            ghi     rf
            str     r9
            inc     r9
            glo     rf
            str     r9                  ; zdisp_pc = target offset
            mov     r9, zdisp_pc_bank
            glo     rd
            str     r9                  ; zdisp_pc_bank = target bank
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

            call    zvar_frame_pop      ; rd = return_pc, rc.0 =
                                        ; return_pc's own bank, rf.0 =
                                        ; store_variable -- NOT in d;
                                        ; zvar_frame_pop's own internal
                                        ; bookkeeping (stack_base
                                        ; restore) runs more arithmetic
                                        ; after setting rf.0/rc.0, so d
                                        ; no longer holds either by the
                                        ; time this returns
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
            mov     r8, zdisp_pc_bank
            glo     rc
            str     r8                  ; zdisp_pc_bank = return_pc's
                                        ; own bank, from zvar_frame_
                                        ; pop's own rc.0 output --
                                        ; captured here, before rc
                                        ; itself gets reused for the
                                        ; return value just below

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
            plo     r8                  ; r8 = operand[0] (packed addr)

; ---- call 0: Z-Machine Standard 6.4.3 -- calling packed address 0 is
; legal and does nothing whatsoever. No frame is pushed, zdisp_pc keeps
; the fallthrough zdisp_step already committed, and the store variable
; simply gets false. Real V3 files depend on it: an object with no
; "action routine" property falls back to a property default of 0 and
; the game calls that unconditionally -- ZORK I does exactly this while
; listing the objects in a room, and without this the interpreter went
; on to read the story HEADER as a routine header (local_count = the
; version byte, 3) and execute the object table as code. Mirrors
; host/dispatch.c's own do_call, fixed in the same pass.
            glo     r8
            lbnz    zdc_real_call
            ghi     r8
            lbnz    zdc_real_call
            mov     rf, 0               ; rf = false, the stored result
            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8                  ; d = store variable (loaded
                                        ; LAST -- mov clobbers d)
            call    zvar_write
            rtn                         ; zvar_write's own df is the
                                        ; result: 0 on success

zdc_real_call:
            glo     r8
            shl
            plo     r8
            ghi     r8
            shlc
            phi     r8                  ; r8 = operand[0]*2, wrapped to
                                        ; 16 bits; DF = the 17th bit --
                                        ; doubling a packed routine
                                        ; address can legitimately
                                        ; carry into it for a story
                                        ; file over 64K (most of the V3
                                        ; sample library), which a
                                        ; plain shl16 would silently
                                        ; discard (same fix as zds_
                                        ; print_paddr's own, same
                                        ; reasoning)
            ldi     0
            plo     r9
            lbnf    zdc_no_carry
            ldi     1
            plo     r9
zdc_no_carry:
            ldi     0
            phi     r9                  ; r9 = routine_addr's own high
                                        ; word

            mov     rb, zdisp_routine_addr
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb                  ; zdisp_routine_addr =
                                        ; routine_addr's low word
            mov     rb, zdisp_routine_addr_hi
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb                  ; zdisp_routine_addr_hi =
                                        ; routine_addr's high word

            mov     rd, r8              ; rd = routine_addr low word
            mov     ra, r9              ; ra = routine_addr high word
            mov     rf, zdisp_call_scratch
            mov     rc, 1
            call    zmread_bytes        ; rc = actual bytes copied (0
                                        ; or 1 -- no partial case for a
                                        ; 1-byte request, so df=1 alone
                                        ; is the right failure check
                                        ; here); df=err
            lbdf    zdc_fail

            mov     r9, zdisp_call_scratch
            ldn     r9                  ; d = local_count byte
            plo     r9                  ; r9.0 = local_count
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

; default = word at (routine_addr_wide + 1 + i*2) -- the routine's own
; wide address plus a small, always-positive delta, computed via
; zwide_add_signed (safe to reuse for a positive delta too) then
; fetched through zmread_bytes (wide-aware, unlike the plain 16-bit
; zmread16 this used before)
            mov     rf, zdisp_i
            ldn     rf
            shl                         ; d = i*2
            adi     1                   ; d = 1+i*2
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:(1+i*2), the delta

            mov     r8, zdisp_routine_addr_hi
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = routine_addr's high word
                                        ; -- BUG FIX: this used to do
                                        ; "ldn r8 / phi rd / ldi 0 / plo
                                        ; rd", which reads only the
                                        ; stored WORD's high byte (always
                                        ; 0) and then puts it in RD's
                                        ; high half as well, so RD came
                                        ; out 0 no matter what. The bank
                                        ; of any routine past 64K was
                                        ; therefore lost: its local
                                        ; defaults were read from bank 0,
                                        ; and zdisp_pc_bank was left 0
                                        ; after the call, so execution
                                        ; resumed at the right OFFSET in
                                        ; the wrong bank. Invisible until
                                        ; a story actually called a
                                        ; routine up there -- ZORK I's
                                        ; first one is its mailbox
                                        ; open/close handler.
            mov     r8, zdisp_routine_addr
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = routine_addr low word
            mov     rc, r9              ; rc = delta
            call    zwide_add_signed    ; rd:rf = target bank:offset

            mov     ra, rd              ; ra = target's high word --
                                        ; stashed before rd itself is
                                        ; reused as zmread_bytes' own
                                        ; low-word input just below
            mov     rd, rf              ; rd = target's low word
            mov     rf, zdisp_call_scratch
            mov     rc, 2
            call    zmread_bytes        ; rc = actual bytes copied
            lbdf    zdc_fail

            mov     r9, zdisp_call_scratch
            lda     r9
            phi     rf
            ldn     r9
            plo     rf                  ; rf = default value (big-
                                        ; endian, from the scratch buf)

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
            mov     r8, zdisp_next_pc_bank
            ldn     r8
            plo     ra                  ; ra.0 = return_pc's own bank

            mov     rf, zdisp_locals

            mov     r8, zdisp_instr+ZDI_STORE_VARIABLE
            ldn     r8
            plo     rc                  ; rc.0 = store_variable
            mov     r8, zdisp_local_count
            ldn     r8
            phi     rc                  ; rc.1 = local_count

            call    zvar_frame_push
            lbdf    zdc_fail

; pc = routine_addr_wide + 1 + local_count*2 (same zwide_add_signed
; pattern as the per-local default reads above)
            mov     r8, zdisp_local_count
            ldn     r8
            shl                         ; d = local_count*2
            adi     1                   ; d = 1+local_count*2
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:(1+local_count*2)

            mov     r8, zdisp_routine_addr_hi
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = routine_addr's high word
                                        ; -- BUG FIX: this used to do
                                        ; "ldn r8 / phi rd / ldi 0 / plo
                                        ; rd", which reads only the
                                        ; stored WORD's high byte (always
                                        ; 0) and then puts it in RD's
                                        ; high half as well, so RD came
                                        ; out 0 no matter what. The bank
                                        ; of any routine past 64K was
                                        ; therefore lost: its local
                                        ; defaults were read from bank 0,
                                        ; and zdisp_pc_bank was left 0
                                        ; after the call, so execution
                                        ; resumed at the right OFFSET in
                                        ; the wrong bank. Invisible until
                                        ; a story actually called a
                                        ; routine up there -- ZORK I's
                                        ; first one is its mailbox
                                        ; open/close handler.
            mov     r8, zdisp_routine_addr
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = routine_addr low word
            mov     rc, r9              ; rc = delta
            call    zwide_add_signed    ; rd:rf = new pc bank:offset

            mov     r8, zdisp_pc
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_pc = new pc offset
            mov     r8, zdisp_pc_bank
            glo     rd
            str     r8                  ; zdisp_pc_bank = new pc bank
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
; for instr.length itself). Routine code (and its own inline print
; text) is routinely placed in high memory, so this can no longer
; assume residency: it fetches the packed bytes through
; zmread_bytes (guest-address, cache-aware, via zmread)
; into zdisp_packed_buf, THEN decodes from there into zdisp_text_buf --
; two separate buffers, since zdec_decode's own output would otherwise
; overwrite input words it hasn't consumed yet if both lived in the
; same place. zdec_decode's own output is already NUL-terminated, so
; the whole decoded string goes to zdisp_emit_string in one call. DF=1
; on a fetch failure (an out-of-range or cache I/O error) or a z-text
; decode failure (a malformed/nested abbreviation reference or a
; zmread/zmread_bytes failure while expanding one -- see zdec.asm's
; own zdec_decode).
            proc    zdisp_print_inline
            mov     r8, zdisp_instr+ZDI_ADDR
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = addr
            add16   r9, 1               ; r9 = addr+1 (skip the
                                        ; opcode byte) -- guest address

            mov     r8, zdisp_instr+ZDI_LENGTH
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = length
            sub16   ra, 1               ; ra = length-1 (packed byte
                                        ; count)

            mov     rd, r9              ; rd = guest address of the
                                        ; packed text
            mov     rf, zdisp_packed_buf
            mov     rc, ra
            mov     r8, zdisp_pc_bank
            ldn     r8
            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:bank -- the text's own
                                        ; bank (phi is needed here: ra
                                        ; still holds its own high byte
                                        ; from the earlier "ra = length"
                                        ; computation above otherwise) --
                                        ; inline text is addr+1 from
                                        ; THIS instruction, whose own
                                        ; bytes (opcode+text) share one
                                        ; bank in every non-straddling
                                        ; case; zdisp_pc_bank already
                                        ; holds exactly that bank here
                                        ; (zdisp_step's own preamble
                                        ; committed it as part of the
                                        ; default-fallthrough pc before
                                        ; dispatching to this handler)
            call    zmread_bytes  ; rc = actual bytes
                                        ; copied; df=1 only if even the
                                        ; very first byte failed
            lbdf    zdpi_fail
            mov     r9, rc              ; r9 = actual bytes copied,
                                        ; stashed before the length
                                        ; reload below reuses rc

            mov     r8, zdisp_instr+ZDI_LENGTH  ; re-read the packed
                                        ; byte count fresh -- ra itself
                                        ; can't be trusted to have
                                        ; survived the fetch call above
                                        ; (zmread's cache path may
                                        ; reach undocumented-clobber
                                        ; K_FILE_* calls, same lesson
                                        ; as zmread_cache_go's own fix)
            lda     r8
            phi     rc
            ldn     r8
            plo     rc
            sub16   rc, 1               ; rc = length-1 (packed byte
                                        ; count) -- what this call
                                        ; originally asked the fetch for

; unlike zdisp_print_at's own deliberately generous, best-effort cap,
; inline text's count is exact (decode_instruction's own has_text scan
; already measured it via zmread) -- a short copy here means that scan
; and this fetch disagree about what's readable, which shouldn't
; happen and isn't safe to paper over
            glo     r9
            str     r2
            glo     rc
            xor
            lbnz    zdpi_fail
            ghi     r9
            str     r2
            ghi     rc
            xor
            lbnz    zdpi_fail

            mov     rd, zdisp_packed_buf
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

; zdisp_print_at (internal): RD = GUEST address of packed z-text (low
; word), RA = that address's high word (both set immediately before
; the call; RA is 0 for print_addr, whose operand is always a plain
; 16-bit byte address, and possibly nonzero for print_paddr, whose
; packed operand*2 can legitimately exceed 65535 in a V3 story file
; over 64K) -- print_addr/print_paddr point at arbitrary story-file
; text, almost always static or high memory, so this fetches through
; zmread_bytes (cache-aware, via zmread_wide) into zdisp_packed_buf
; before decoding into zdisp_text_buf, the same two-buffer split
; zdisp_print_inline uses and for the same reason. Uses a generous
; fixed length (matching both buffers' own
; capacity) rather than a caller-supplied one -- unlike inline text
; (measured by decode_instruction's own has_text scan) or an object's
; short name (measured by zobj_short_name), print_addr/print_paddr
; have no prior length measurement anywhere in this pipeline. Safe
; because zdec_decode itself stops at the real end-of-string word
; regardless of how much of the given length goes unused (see
; zdec.asm's own zdec_word_done), matching the "trust the input"
; boundary both buffers' own declarations already document -- and
; zmread_bytes returns whatever it actually managed to copy
; (short of 512 near a real story file's own end is a normal outcome,
; not a failure) rather than requiring the full generous request to
; succeed, so a short story nearing the end of its own file doesn't
; need padding.
            proc    zdisp_print_at
            mov     rf, zdisp_packed_buf
            mov     rc, 512
            call    zmread_bytes  ; rc = actual bytes
                                        ; copied (<=512); df=1 only if
                                        ; even the very first byte
                                        ; failed
            lbdf    zdpa_fail

            mov     rd, zdisp_packed_buf    ; rc already holds the
                                        ; actual copied count from the
                                        ; fetch above -- consumed
                                        ; directly, nothing called in
                                        ; between to put it at risk
            mov     rf, zdisp_text_buf
            call    zdec_decode
            lbdf    zdpa_fail

            mov     rf, zdisp_text_buf
            call    zdisp_emit_string
            clc
            rtn

zdpa_fail:
            stc
            rtn
            endp

; zrand_shl32 (internal): RD:R8 = 32-bit value (RD=high word, R8=low
; word), D = shift count 0-31 (set immediately before the call).
; Returns RD:R8 = value << count, zero-filled, via native SHL/SHLC
; (matches lib/fmt32.asm's own _div32_by10 shift technique).
            proc    zrand_shl32
            plo     r7                  ; r7.0 = remaining count
zrsl_loop:
            glo     r7
            lbz     zrsl_done

            glo     r8
            shl
            plo     r8
            ghi     r8
            shlc
            phi     r8
            glo     rd
            shlc
            plo     rd
            ghi     rd
            shlc
            phi     rd

            dec     r7
            lbr     zrsl_loop
zrsl_done:
            rtn
            endp

; zrand_shr32 (internal): RD:R8 = 32-bit value, D = shift count 0-31
; (set immediately before the call). Returns RD:R8 = value >> count,
; zero-filled, via native SHR/SHRC (the mirror-image walk, high byte
; to low byte).
            proc    zrand_shr32
            plo     r7
zrsr_loop:
            glo     r7
            lbz     zrsr_done

            ghi     rd
            shr
            phi     rd
            glo     rd
            shrc
            plo     rd
            ghi     r8
            shrc
            phi     r8
            glo     r8
            shrc
            plo     r8

            dec     r7
            lbr     zrsr_loop
zrsr_done:
            rtn
            endp

; zrand_stash (internal): stores RD:R8 into zrand_tmp.
            proc    zrand_stash
            mov     r9, zrand_tmp
            ghi     rd
            str     r9
            inc     r9
            glo     rd
            str     r9
            inc     r9
            ghi     r8
            str     r9
            inc     r9
            glo     r8
            str     r9
            rtn
            endp

; zrand_xor_tmp (internal): RD:R8 ^= the 4 bytes at zrand_tmp, in
; place.
            proc    zrand_xor_tmp
            mov     r9, zrand_tmp
            lda     r9
            str     r2
            ghi     rd
            xor
            phi     rd
            lda     r9
            str     r2
            glo     rd
            xor
            plo     rd
            lda     r9
            str     r2
            ghi     r8
            xor
            phi     r8
            ldn     r9
            str     r2
            glo     r8
            xor
            plo     r8
            rtn
            endp

; zrand_step (internal, no arguments): advances zrand_state via the
; xorshift32 algorithm (x^=x<<13; x^=x>>17; x^=x<<5 -- same constants
; and technique as host/vm_state.c's own xorshift32), persisting the
; new state and returning it in RD:R8 (RD=high word, R8=low word).
; zds_random only consumes R8 (the low 16 bits) for its own modulo
; draw -- unlike host's exact 32-bit modulo, this port draws from the
; low word alone, a deliberate simplification (the Z-machine standard
; doesn't mandate bit-exact PRNG behavior, only plausible randomness)
; made to avoid a 32-by-16 divide when a 16-by-16 one (zdisp_umod16,
; also reusable for the still-deferred div/mod opcodes) already
; suffices.
            proc    zrand_step
            mov     r9, zrand_state
            lda     r9
            phi     rd
            lda     r9
            plo     rd
            lda     r9
            phi     r8
            ldn     r9
            plo     r8                  ; rd:r8 = current state

            call    zrand_stash
            ldi     13
            call    zrand_shl32
            call    zrand_xor_tmp       ; x ^= x << 13

            call    zrand_stash
            ldi     17
            call    zrand_shr32
            call    zrand_xor_tmp       ; x ^= x >> 17

            call    zrand_stash
            ldi     5
            call    zrand_shl32
            call    zrand_xor_tmp       ; x ^= x << 5

            mov     r9, zrand_state
            ghi     rd
            str     r9
            inc     r9
            glo     rd
            str     r9
            inc     r9
            ghi     r8
            str     r9
            inc     r9
            glo     r8
            str     r9                  ; persist the new state

            clc
            rtn
            endp

; zdisp_umod16 (internal): RD = dividend, RF = divisor, both 16-bit
; unsigned (set immediately before the call). Returns RD = dividend
; mod divisor. DF=1 if divisor is 0. 16-iteration restoring bit-by-bit
; division (same technique as lib/fmt32.asm's own _div32_by10,
; generalized from a fixed divisor to a runtime one, and from a
; 32-bit/8-bit-remainder shape to 16-bit/16-bit-remainder, since a
; general divisor's remainder no longer fits in one byte).
            proc    zdisp_umod16
            glo     rf
            lbnz    zum_have_divisor
            ghi     rf
            lbnz    zum_have_divisor
            stc
            rtn

zum_have_divisor:
            mov     r7, rd              ; r7 = dividend (shifted left
                                        ; one bit per iteration)
            ldi     16
            plo     rb                  ; rb.0 = iteration count
            ldi     0
            plo     rc
            phi     rc                  ; rc = 0 (16-bit remainder
                                        ; accumulator)

zum_loop:
            glo     rb
            lbz     zum_done

            glo     r7
            shl
            plo     r7
            ghi     r7
            shlc
            phi     r7                  ; r7 <<= 1; DF = bit that fell
                                        ; off bit15

            glo     rc
            shlc
            plo     rc                  ; rc.lo <<= 1, carry-in = the
                                        ; bit that fell off r7
            ghi     rc
            shlc
            phi     rc                  ; rc.hi <<= 1, carry-in = the
                                        ; bit that fell off rc.lo --
                                        ; low-to-high order, same
                                        ; chaining direction as r7's
                                        ; own shift above and
                                        ; zrand_shl32's (this was
                                        ; backwards before: shifting
                                        ; rc.hi first fed r7's outgoing
                                        ; bit into the wrong end)

            mov     r8, rc
            sub16   r8, rf              ; r8 = rc - rf; DF=1 (no
                                        ; borrow) means rc >= rf
            lbnf    zum_no_sub
            mov     rc, r8              ; commit: rc -= rf

zum_no_sub:
            dec     rb
            lbr     zum_loop

zum_done:
            mov     rd, rc
            clc
            rtn
            endp

; zdisp_udivmod16 (internal): RD = dividend, RF = divisor, both 16-bit
; unsigned (set immediately before the call). Returns RD = quotient,
; RF = remainder. DF=1 if divisor is 0. Same 16-iteration restoring
; division as zdisp_umod16 just above (same r7/rc shift chain, same
; low-to-high SHL/SHLC threading of the bit that falls off r7 into
; rc), kept as its own routine rather than folding into zdisp_umod16
; itself so zdisp_umod16's own already-verified caller (random) is
; untouched. The quotient (r8) needs no external carry threaded in --
; its own new bit is either 0 (default) or set to 1 explicitly when a
; trial subtraction commits -- so it shifts with the plain shl16
; macro instead of a manual chain.
            proc    zdisp_udivmod16
            glo     rf
            lbnz    zud_have_divisor
            ghi     rf
            lbnz    zud_have_divisor
            stc
            rtn

zud_have_divisor:
            mov     r9, rf              ; r9 = divisor (survives the
                                        ; whole loop; rf itself is
                                        ; reused for the remainder
                                        ; result at the end)
            mov     r7, rd              ; r7 = dividend (shifted left
                                        ; one bit per iteration)
            ldi     16
            plo     rb                  ; rb.0 = iteration count
            ldi     0
            plo     rc
            phi     rc                  ; rc = 0 (remainder
                                        ; accumulator)
            ldi     0
            plo     r8
            phi     r8                  ; r8 = 0 (quotient accumulator)

zud_loop:
            glo     rb
            lbz     zud_done

            glo     r7
            shl
            plo     r7
            ghi     r7
            shlc
            phi     r7                  ; r7 <<= 1; DF = bit that fell
                                        ; off bit15

            glo     rc
            shlc
            plo     rc
            ghi     rc
            shlc
            phi     rc                  ; rc <<= 1, carry-in = the bit
                                        ; that fell off r7 -- same low-
                                        ; to-high chaining as
                                        ; zdisp_umod16 above

            shl16   r8                  ; quotient <<= 1, zero-filled

            mov     rd, rc
            sub16   rd, r9              ; rd = rc - r9; DF=1 (no
                                        ; borrow) means rc >= r9
            lbnf    zud_no_sub
            mov     rc, rd              ; commit: rc -= r9
            glo     r8
            ori     1
            plo     r8                  ; set quotient's new bit0

zud_no_sub:
            dec     rb
            lbr     zud_loop

zud_done:
            mov     rd, r8              ; rd = quotient
            mov     rf, rc              ; rf = remainder
            clc
            rtn
            endp

; zdisp_sdivmod16 (internal): RD = dividend, RF = divisor, both signed
; 16-bit (set immediately before the call). Returns RD = quotient,
; RC = remainder, both signed -- truncating toward zero with the
; remainder taking the dividend's sign, matching the Z-machine spec
; (and C's own convention). DF=1 if divisor is 0, propagated straight
; from zdisp_udivmod16. Computes both results from one division so
; div/mod's shared sign bookkeeping is written once, not twice.
            proc    zdisp_sdivmod16
            mov     r8, zdisp_value
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8                  ; zdisp_value = dividend's
                                        ; original value -- spilled to
                                        ; memory, NOT kept in r8,
                                        ; because zdisp_udivmod16 below
                                        ; clobbers r8 (its own quotient
                                        ; accumulator) and r9 (its own
                                        ; divisor copy); nothing needed
                                        ; after that call can survive
                                        ; in either register
            mov     r8, zdisp_value2
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8                  ; zdisp_value2 = divisor's
                                        ; original value

            ghi     rd
            ani     $80
            lbz     zsd_dividend_pos
            ghi     rd
            not
            phi     rd
            glo     rd
            not
            plo     rd
            add16   rd, 1               ; rd = |dividend|
zsd_dividend_pos:

            ghi     rf
            ani     $80
            lbz     zsd_divisor_pos
            ghi     rf
            not
            phi     rf
            glo     rf
            not
            plo     rf
            add16   rf, 1               ; rf = |divisor|
zsd_divisor_pos:

            call    zdisp_udivmod16     ; rd = |quotient|, rf =
                                        ; |remainder|; df=1 if the
                                        ; divisor was 0
            lbdf    zsd_fail

            mov     rc, rf              ; rc = |remainder|, moved out
                                        ; of rf before rf is clobbered
                                        ; by the byte-compare idiom
                                        ; below

; quotient sign: negative iff the two original operands' signs
; differed (same register-compare-via-memory idiom as zcache.asm's own
; offset check -- the 1802 has no register-register xor). Both
; operands are reloaded from zdisp_value/zdisp_value2, not r8/r9 (see
; this proc's own header note above).
            mov     r8, zdisp_value
            lda     r8                  ; d = dividend's original high
                                        ; byte
            str     r2
            mov     r8, zdisp_value2
            ldn     r8                  ; d = divisor's original high
                                        ; byte
            xor
            ani     $80
            lbz     zsd_quotient_pos
            ghi     rd
            not
            phi     rd
            glo     rd
            not
            plo     rd
            add16   rd, 1               ; rd = -quotient
zsd_quotient_pos:

; remainder sign: matches the dividend's original sign
            mov     r8, zdisp_value
            ldn     r8                  ; d = dividend's original high
                                        ; byte
            ani     $80
            lbz     zsd_done
            ghi     rc
            not
            phi     rc
            glo     rc
            not
            plo     rc
            add16   rc, 1               ; rc = -remainder
zsd_done:
            clc
            rtn

zsd_fail:
            stc
            rtn
            endp

            proc    _zdispatch_data
zdisp_pc:            dw      0
zdisp_pc_bank:       db      0       ; zdisp_pc's own high word/bank --
                                    ; a V3 story file over 64K (most of
                                    ; the sample library) can have code
                                    ; beyond the first 64K, which a
                                    ; plain 16-bit zdisp_pc can't
                                    ; represent on its own
zdisp_quit:           db      0
zdisp_i:              db      0
zdisp_next_pc:         dw      0
zdisp_next_pc_bank:    db      0
zdisp_value:            dw      0
zdisp_value2:           dw      0       ; second scratch word, for
                                        ; opcodes that need two 16-bit
                                        ; values to survive a zvar_*
                                        ; call (dec_chk/inc_chk's own
                                        ; updated value + threshold)
zdisp_routine_addr:      dw      0
zdisp_routine_addr_hi:   dw      0
zdisp_local_count:        db      0
zdisp_call_scratch:       ds      2       ; zdisp_do_call's own 1-2
                                        ; byte staging area for its
                                        ; zmread_bytes-based reads (the
                                        ; routine header's local_count
                                        ; byte, and each local's own
                                        ; default value word) -- needed
                                        ; since those addresses can
                                        ; legitimately exceed 65535 in
                                        ; a V3 story file over 64K, and
                                        ; zmread_bytes (unlike the
                                        ; plain 16-bit zmread/zmread16)
                                        ; is the one primitive here
                                        ; that's already wide-aware
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
zdisp_packed_buf:              ds      512     ; raw packed z-text
                                              ; bytes staged here by
                                              ; zmread_bytes
                                              ; before zdec_decode runs
                                              ; -- kept separate from
                                              ; zdisp_text_buf (the
                                              ; DECODED output) since
                                              ; decode can't safely
                                              ; write its own output
                                              ; over not-yet-consumed
                                              ; input in the same
                                              ; buffer
zdisp_newline_buf:             db      10, 0   ; a constant 2-byte
                                              ; NUL-terminated "\n",
                                              ; reused by both
                                              ; print_ret and new_line
zdisp_char_buf:                ds      2       ; print_char's own
                                              ; 1-char + NUL buffer
zdisp_num_buf:                 ds      12      ; print_num's own
                                              ; '-' + up to 10 digits
                                              ; (ym_fmt_uint32's own
                                              ; documented minimum) + NUL
zrand_state:                   dw      $9e37, $79b9   ; xorshift32's
                                              ; own state -- fixed
                                              ; nonzero default seed
                                              ; (no entropy source at
                                              ; program start; see
                                              ; zrand_step's own header
                                              ; for the range==0
                                              ; reseed path)
zrand_tmp:                     ds      4       ; zrand_stash/xor_tmp's
                                              ; own 32-bit scratch

                public  zdisp_pc
                public  zdisp_pc_bank
                public  zdisp_quit
                public  zdisp_i
                public  zdisp_next_pc
                public  zdisp_next_pc_bank
                public  zdisp_value
                public  zdisp_value2
                public  zdisp_routine_addr
                public  zdisp_routine_addr_hi
                public  zdisp_local_count
                public  zdisp_call_scratch
                public  zdisp_instr
                public  zdisp_operand
                public  zdisp_locals
                public  zdisp_text_buf
                public  zdisp_packed_buf
                public  zdisp_newline_buf
                public  zdisp_char_buf
                public  zdisp_num_buf
                public  zrand_state
                public  zrand_tmp
            endp
