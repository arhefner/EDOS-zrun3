;
; zdecodediag.asm - self-contained diagnostic dispatch for the V3
; instruction decoder (zdecode.asm)
;
; Exercises decode_instruction against the same hand-derived byte
; sequences validated on the host (tests/test_host.c's decoder block,
; and re-verified by hand against this port before it was written) --
; one check per instruction form/feature: long-form 2OP with a store,
; short-form 1OP with a single-byte branch, variable-form VAR with
; omitted trailing operands, short-form 0OP with inline text, long-
; form 2OP with a two-byte negative branch offset (the sign-extension
; path), and a truncated-instruction failure case. Checks 0-4 also
; verify instr.addr itself (== 0, since every one of them decodes at
; guest address 0) -- added after a real bug (zdi_finalize wrote a
; leftover zde_fieldptr offset instead of the real address, because
; the call to zde_put16 for instr.length clobbers r9 after it, not
; before) went undetected here for a full round of hardware testing;
; nothing in this file had ever asserted on addr before. Touches no
; ELF-DOS kernel or BIOS entry points.
;

#include    include/opcodes.def
#include    include/zdecode.inc

            extrn   zminit
            extrn   zdecode_instruction

            extrn   zdd_field

            extrn   zdd_mem
            extrn   zdd_instr
            extrn   zdd_results

ZDDIAG_COUNT:   equ     6

; zdd_field (internal): D = offset into the instruction buffer. Returns
; D = the byte at zdd_instr + offset.
            proc    zdd_field
            plo     r9
            ldi     0
            phi     r9
            mov     rf, zdd_instr
            add16   rf, r9
            ldn     rf
            clc
            rtn
            endp

; zddiag_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zdd_results[0..ZDDIAG_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail), in the order described below.
            proc    zddiag_run
            mov     rd, zdd_mem
            mov     rf, 32
            call    zminit              ; guest addresses 0..31

; check 0: long form, 2OP:20 "add", two small constants, stores:
; opcode byte $14 (long form, both operands small const, opcode 20),
; operands 5 and 3, store variable $10
            mov     rf, zdd_mem
            ldi     $14
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     3
            str     rf
            inc     rf
            ldi     $10
            str     rf

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbdf    zdd_fail0

            ldi     ZDI_ADDR
            call    zdd_field
            lbnz    zdd_fail0
            ldi     ZDI_ADDR+1
            call    zdd_field
            lbnz    zdd_fail0
            ldi     ZDI_FORM
            call    zdd_field
            xri     ZDI_FORM_LONG
            lbnz    zdd_fail0
            ldi     ZDI_CATEGORY
            call    zdd_field
            xri     ZDI_CAT_2OP
            lbnz    zdd_fail0
            ldi     ZDI_OPCODE
            call    zdd_field
            xri     20
            lbnz    zdd_fail0
            ldi     ZDI_OPERAND_COUNT
            call    zdd_field
            xri     2
            lbnz    zdd_fail0
            ldi     ZDI_OPERAND_TYPES
            call    zdd_field
            xri     1                   ; SMALL
            lbnz    zdd_fail0
            ldi     ZDI_OPERAND_TYPES+1
            call    zdd_field
            xri     1
            lbnz    zdd_fail0
            ldi     ZDI_OPERANDS+1
            call    zdd_field           ; operands[0] low byte (high
                                        ; byte is 0 for both operands
                                        ; below, not separately checked)
            xri     5
            lbnz    zdd_fail0
            ldi     ZDI_OPERANDS+3
            call    zdd_field           ; operands[1] low byte
            xri     3
            lbnz    zdd_fail0
            ldi     ZDI_STORES
            call    zdd_field
            xri     1
            lbnz    zdd_fail0
            ldi     ZDI_STORE_VARIABLE
            call    zdd_field
            xri     $10
            lbnz    zdd_fail0
            ldi     ZDI_BRANCHES
            call    zdd_field
            lbnz    zdd_fail0
            ldi     ZDI_HAS_TEXT
            call    zdd_field
            lbnz    zdd_fail0
            ldi     ZDI_LENGTH+1
            call    zdd_field
            xri     4
            lbnz    zdd_fail0

            mov     rb, zdd_results+0
            ldi     0
            lbr     zdd_store0
zdd_fail0:  mov     rb, zdd_results+0
            ldi     1
zdd_store0: str     rb

; check 1: short form, 1OP:0 "jz", one variable operand, branches:
; opcode byte $A0 (short form, operand type variable, opcode 0),
; operand = variable 5, then a single-byte branch (on true, offset 10)
; $CA
            mov     rf, zdd_mem
            ldi     $a0
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     $ca
            str     rf

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbdf    zdd_fail1

            ldi     ZDI_ADDR
            call    zdd_field
            lbnz    zdd_fail1
            ldi     ZDI_ADDR+1
            call    zdd_field
            lbnz    zdd_fail1
            ldi     ZDI_FORM
            call    zdd_field
            xri     ZDI_FORM_SHORT
            lbnz    zdd_fail1
            ldi     ZDI_CATEGORY
            call    zdd_field
            xri     ZDI_CAT_1OP
            lbnz    zdd_fail1
            ldi     ZDI_OPCODE
            call    zdd_field
            lbnz    zdd_fail1
            ldi     ZDI_OPERAND_COUNT
            call    zdd_field
            xri     1
            lbnz    zdd_fail1
            ldi     ZDI_OPERAND_TYPES
            call    zdd_field
            xri     2                   ; VARIABLE
            lbnz    zdd_fail1
            ldi     ZDI_OPERANDS+1
            call    zdd_field
            xri     5
            lbnz    zdd_fail1
            ldi     ZDI_STORES
            call    zdd_field
            lbnz    zdd_fail1
            ldi     ZDI_BRANCHES
            call    zdd_field
            xri     1
            lbnz    zdd_fail1
            ldi     ZDI_BRANCH_ON_TRUE
            call    zdd_field
            xri     1
            lbnz    zdd_fail1
            ldi     ZDI_BRANCH_OFFSET+1
            call    zdd_field
            xri     10
            lbnz    zdd_fail1
            ldi     ZDI_LENGTH+1
            call    zdd_field
            xri     3
            lbnz    zdd_fail1

            mov     rb, zdd_results+1
            ldi     0
            lbr     zdd_store1
zdd_fail1:  mov     rb, zdd_results+1
            ldi     1
zdd_store1: str     rb

; check 2: variable form, VAR:0 "call", stores: opcode byte $E0
; (variable form, VAR category, opcode 0), operand types byte $1F
; (large, small, omitted, omitted), operands $0800 and 7, store
; variable $11
            mov     rf, zdd_mem
            ldi     $e0
            str     rf
            inc     rf
            ldi     $1f
            str     rf
            inc     rf
            ldi     $08
            str     rf
            inc     rf
            ldi     $00
            str     rf
            inc     rf
            ldi     7
            str     rf
            inc     rf
            ldi     $11
            str     rf

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbdf    zdd_fail2

            ldi     ZDI_ADDR
            call    zdd_field
            lbnz    zdd_fail2
            ldi     ZDI_ADDR+1
            call    zdd_field
            lbnz    zdd_fail2
            ldi     ZDI_FORM
            call    zdd_field
            xri     ZDI_FORM_VARIABLE
            lbnz    zdd_fail2
            ldi     ZDI_CATEGORY
            call    zdd_field
            xri     ZDI_CAT_VAR
            lbnz    zdd_fail2
            ldi     ZDI_OPCODE
            call    zdd_field
            lbnz    zdd_fail2
            ldi     ZDI_OPERAND_COUNT
            call    zdd_field
            xri     2
            lbnz    zdd_fail2
            ldi     ZDI_OPERAND_TYPES
            call    zdd_field
            lbnz    zdd_fail2           ; LARGE == 0
            ldi     ZDI_OPERAND_TYPES+1
            call    zdd_field
            xri     1                   ; SMALL
            lbnz    zdd_fail2
            ldi     ZDI_OPERANDS
            call    zdd_field
            xri     $08
            lbnz    zdd_fail2
            ldi     ZDI_OPERANDS+1
            call    zdd_field
            lbnz    zdd_fail2
            ldi     ZDI_OPERANDS+3
            call    zdd_field
            xri     7
            lbnz    zdd_fail2
            ldi     ZDI_STORES
            call    zdd_field
            xri     1
            lbnz    zdd_fail2
            ldi     ZDI_STORE_VARIABLE
            call    zdd_field
            xri     $11
            lbnz    zdd_fail2
            ldi     ZDI_LENGTH+1
            call    zdd_field
            xri     6
            lbnz    zdd_fail2

            mov     rb, zdd_results+2
            ldi     0
            lbr     zdd_store2
zdd_fail2:  mov     rb, zdd_results+2
            ldi     1
zdd_store2: str     rb

; check 3: short form, 0OP:2 "print", carries an inline packed string
; -- reuses the exact "hello" bytes from ztext_decode's own test
            mov     rf, zdd_mem
            ldi     $b2
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

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbdf    zdd_fail3

            ldi     ZDI_ADDR
            call    zdd_field
            lbnz    zdd_fail3
            ldi     ZDI_ADDR+1
            call    zdd_field
            lbnz    zdd_fail3
            ldi     ZDI_FORM
            call    zdd_field
            xri     ZDI_FORM_SHORT
            lbnz    zdd_fail3
            ldi     ZDI_CATEGORY
            call    zdd_field
            xri     ZDI_CAT_0OP
            lbnz    zdd_fail3
            ldi     ZDI_OPCODE
            call    zdd_field
            xri     2
            lbnz    zdd_fail3
            ldi     ZDI_OPERAND_COUNT
            call    zdd_field
            lbnz    zdd_fail3
            ldi     ZDI_STORES
            call    zdd_field
            lbnz    zdd_fail3
            ldi     ZDI_BRANCHES
            call    zdd_field
            lbnz    zdd_fail3
            ldi     ZDI_HAS_TEXT
            call    zdd_field
            xri     1
            lbnz    zdd_fail3
            ldi     ZDI_LENGTH+1
            call    zdd_field
            xri     5
            lbnz    zdd_fail3

            mov     rb, zdd_results+3
            ldi     0
            lbr     zdd_store3
zdd_fail3:  mov     rb, zdd_results+3
            ldi     1
zdd_store3: str     rb

; check 4: long form, 2OP:4 "dec_chk", both operands variables,
; branches with a two-byte offset of -50: opcode byte $64 (long form,
; both operands variable, opcode 4), operands = variables 5 and 6,
; branch bytes $3F,$CE (on false, two-byte form, 14-bit value $3FCE =
; 16334, sign-extends to -50)
            mov     rf, zdd_mem
            ldi     $64
            str     rf
            inc     rf
            ldi     5
            str     rf
            inc     rf
            ldi     6
            str     rf
            inc     rf
            ldi     $3f
            str     rf
            inc     rf
            ldi     $ce
            str     rf

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbdf    zdd_fail4

            ldi     ZDI_ADDR
            call    zdd_field
            lbnz    zdd_fail4
            ldi     ZDI_ADDR+1
            call    zdd_field
            lbnz    zdd_fail4
            ldi     ZDI_FORM
            call    zdd_field
            xri     ZDI_FORM_LONG
            lbnz    zdd_fail4
            ldi     ZDI_CATEGORY
            call    zdd_field
            xri     ZDI_CAT_2OP
            lbnz    zdd_fail4
            ldi     ZDI_OPCODE
            call    zdd_field
            xri     4
            lbnz    zdd_fail4
            ldi     ZDI_OPERAND_COUNT
            call    zdd_field
            xri     2
            lbnz    zdd_fail4
            ldi     ZDI_OPERAND_TYPES
            call    zdd_field
            xri     2                   ; VARIABLE
            lbnz    zdd_fail4
            ldi     ZDI_OPERAND_TYPES+1
            call    zdd_field
            xri     2
            lbnz    zdd_fail4
            ldi     ZDI_OPERANDS+1
            call    zdd_field
            xri     5
            lbnz    zdd_fail4
            ldi     ZDI_OPERANDS+3
            call    zdd_field
            xri     6
            lbnz    zdd_fail4
            ldi     ZDI_STORES
            call    zdd_field
            lbnz    zdd_fail4
            ldi     ZDI_BRANCHES
            call    zdd_field
            xri     1
            lbnz    zdd_fail4
            ldi     ZDI_BRANCH_ON_TRUE
            call    zdd_field
            lbnz    zdd_fail4
            ldi     ZDI_BRANCH_OFFSET
            call    zdd_field
            xri     $ff
            lbnz    zdd_fail4
            ldi     ZDI_BRANCH_OFFSET+1
            call    zdd_field
            xri     $ce
            lbnz    zdd_fail4
            ldi     ZDI_LENGTH+1
            call    zdd_field
            xri     5
            lbnz    zdd_fail4

            mov     rb, zdd_results+4
            ldi     0
            lbr     zdd_store4
zdd_fail4:  mov     rb, zdd_results+4
            ldi     1
zdd_store4: str     rb

; check 5: a truncated instruction (operand runs past the story's own
; length) is a decode error, not a crash -- "add" needs 4 bytes but
; only 2 are resident
            mov     rd, zdd_mem
            mov     rf, 2
            call    zminit              ; guest addresses 0..1 only

            mov     rf, zdd_mem
            ldi     $14
            str     rf
            inc     rf
            ldi     5
            str     rf

            mov     rd, 0
            mov     rf, zdd_instr
            call    zdecode_instruction
            lbnf    zdd_fail5           ; must fail (DF=1)

            mov     rb, zdd_results+5
            ldi     0
            lbr     zdd_store5
zdd_fail5:  mov     rb, zdd_results+5
            ldi     1
zdd_store5: str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zdd_results
            ldi     ZDDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zdd_tally:
            lda     rb
            lbz     zdd_tally_next
            inc     rf
zdd_tally_next:
            dec     r9
            glo     r9
            lbnz    zdd_tally
            glo     rf
            lbnz    zdd_fail_return
            clc
            rtn
zdd_fail_return:
            stc
            rtn
            endp

            proc    _zdecodediag_data
zdd_mem:        ds      32
zdd_instr:      ds      ZDI_SIZE
zdd_results:    ds      ZDDIAG_COUNT
                public  zdd_mem
                public  zdd_instr
                public  zdd_results
            endp
