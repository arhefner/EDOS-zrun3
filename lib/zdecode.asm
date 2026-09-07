;
; zdecode.asm - V3 instruction decoder
;
; Mirrors host/decode.c's decode_instruction exactly: pure syntactic
; decode (form/category/opcode/operands/store/branch/inline-text
; shape), never opcode semantics, and never fails on an opcode number
; it doesn't recognize -- only on a truncated/malformed read (an
; operand, store byte, branch byte, or inline string running past
; resident memory, propagated from zmread's own DF=1). Recognizing
; opcodes is dispatch's job, not this module's, exactly as the host
; file's own header comment states.
;
; zdecode_instruction(RD = guest address, RF = caller-supplied
; instruction buffer, ZDI_SIZE bytes -- see include/zdecode.inc for
; the field layout) returns DF=1 for a malformed/truncated
; instruction; the buffer may be partially written in that case,
; matching zparse_tokenize's own "partially written on failure"
; contract.
;
; The four opcode "shape" tables (does this opcode store a result,
; branch, or carry an inline packed string -- shape, not semantics,
; same distinction host/decode.c's own tables draw) are packed one
; byte per opcode: bit 0 = stores, bit 1 = branches, bit 2 = has_text.
;
; Register discipline: RD is the live cursor throughout (zmread's own
; address parameter, advanced by an explicit `inc rd` after each byte
; read -- zmread never modifies it). zmread itself clobbers R8/R9/RB/RF,
; so nothing this module needs to survive a byte/word read is ever held
; in those four; R7/RA/RC are used for exactly that (a value that must
; live across a zde_read_byte/zde_read_word call), reloaded from the
; zde_* scratch fields or the instruction buffer itself wherever it
; isn't. This is the same "everything that crosses a call lives in a
; register only R7/R9/RA/RB/RC keep it, or in memory otherwise"
; discipline zparse.asm documents for exactly the same reason (its own
; calls -- zdict_find_word -- have a wide clobber set too).
;
; Only R7-RD and RF are ever used as scratch (no R1, no RE).
;

#include    include/opcodes.def
#include    include/zdecode.inc

            extrn   zmread

            extrn   zde_read_byte
            extrn   zde_read_word
            extrn   zde_fieldptr
            extrn   zde_get8
            extrn   zde_put8
            extrn   zde_put16

            extrn   zde_addr
            extrn   zde_instr
            extrn   zde_opidx
            extrn   zde_fail_addr

            extrn   zde_shape_0op_table
            extrn   zde_shape_1op_table
            extrn   zde_shape_2op_table
            extrn   zde_shape_var_table

            proc    zdecode_instruction
            mov     rb, zde_addr
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb                  ; zde_addr = addr (stash the
                                        ; ORIGINAL address before rd
                                        ; becomes the live cursor)

            mov     rb, zde_instr
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb                  ; zde_instr = instr buffer ptr

            call    zde_read_byte       ; d = opcode byte, rd = addr+1
            lbdf    zdi_error
            plo     r7                  ; r7.0 = opcode_byte -- no call
                                        ; happens before every branch
                                        ; below is done reading it

            glo     r7
            ani     $c0
            xri     $c0
            lbz     zdi_var_form

            glo     r7
            ani     $c0
            xri     $80
            lbz     zdi_short_form

            lbr     zdi_long_form

; ---- variable form: 2OP (bit 5 clear) or VAR (bit 5 set), up to 4
; operands whose types come from a following type byte ----
zdi_var_form:
            ldi     ZDI_FORM_VARIABLE
            plo     rc
            ldi     ZDI_FORM
            call    zde_put8

            glo     r7
            ani     $20
            lbz     zdvf_is_2op
            ldi     ZDI_CAT_VAR
            plo     rc
            lbr     zdvf_have_cat
zdvf_is_2op:
            ldi     ZDI_CAT_2OP
            plo     rc
zdvf_have_cat:
            ldi     ZDI_CATEGORY
            call    zde_put8

            glo     r7
            ani     $1f
            plo     rc
            ldi     ZDI_OPCODE
            call    zde_put8

            call    zde_read_byte       ; d = operand-types byte
            lbdf    zdi_error
            plo     r7                  ; r7.0 = types byte (opcode_byte
                                        ; is no longer needed -- already
                                        ; written to the buffer)

            mov     rb, zde_opidx
            ldi     0
            str     rb                  ; zde_opidx = 0

; Each iteration tests the CURRENT top two bits of r7.0 (six single-
; bit shifts of a copy, then mask -- the same "many chained shifts for
; clarity over a barrel-shifter trick" style zdec.asm's own z-char
; extraction uses), then left-shifts r7.0 itself by two bits so the
; next pair becomes the new top two for the following iteration.
zdvf_type_loop:
            glo     r7
            shr
            shr
            shr
            shr
            shr
            shr                         ; d = types_byte >> 6
            ani     3
            xri     3
            lbz     zdvf_types_done     ; == 3: omitted, stop here

            xri     3                   ; undo (xor is its own inverse):
                                        ; d = the top two bits again --
                                        ; 0=large,1=small,2=variable is
                                        ; already the exact encoding
                                        ; operand_types wants, no
                                        ; further mapping needed
            plo     rc
            mov     rb, zde_opidx
            ldn     rb
            adi     ZDI_OPERAND_TYPES
            call    zde_put8            ; operand_types[opidx] = bits

            mov     rb, zde_opidx
            ldn     rb
            adi     1
            str     rb                  ; zde_opidx += 1 (d still holds
                                        ; the new value; str doesn't
                                        ; touch d)
            smi     4
            lbnf    zdvf_next_pair      ; new opidx < 4: keep going
            lbr     zdvf_types_done

zdvf_next_pair:
            glo     r7
            shl
            shl                         ; types_byte <<= 2 -- drop the
                                        ; pair just consumed, bring the
                                        ; next one to the top
            plo     r7
            lbr     zdvf_type_loop

zdvf_types_done:
            mov     rb, zde_opidx
            ldn     rb
            plo     rc
            ldi     ZDI_OPERAND_COUNT
            call    zde_put8
            lbr     zdi_read_operands

; ---- short form: 0OP (operand-type bits == 3) or 1OP (one operand) ----
zdi_short_form:
            ldi     ZDI_FORM_SHORT
            plo     rc
            ldi     ZDI_FORM
            call    zde_put8

            glo     r7
            ani     $0f
            plo     rc
            ldi     ZDI_OPCODE
            call    zde_put8

            glo     r7
            shr
            shr
            shr
            shr
            ani     3                   ; d = (opcode_byte >> 4) & 3
            xri     3
            lbz     zdsf_0op

            xri     3                   ; undo: d = optype_bits again
                                        ; (0=large,1=small,2=variable,
                                        ; already the right encoding)
            plo     rc
            ldi     ZDI_OPERAND_TYPES
            call    zde_put8

            ldi     ZDI_CAT_1OP
            plo     rc
            ldi     ZDI_CATEGORY
            call    zde_put8

            ldi     1
            plo     rc
            ldi     ZDI_OPERAND_COUNT
            call    zde_put8
            lbr     zdi_read_operands

zdsf_0op:
            ldi     ZDI_CAT_0OP
            plo     rc
            ldi     ZDI_CATEGORY
            call    zde_put8

            ldi     0
            plo     rc
            ldi     ZDI_OPERAND_COUNT
            call    zde_put8
            lbr     zdi_read_operands

; ---- long form: always 2OP, exactly two operands, each small or
; variable per one bit of the opcode byte ----
zdi_long_form:
            ldi     ZDI_FORM_LONG
            plo     rc
            ldi     ZDI_FORM
            call    zde_put8

            ldi     ZDI_CAT_2OP
            plo     rc
            ldi     ZDI_CATEGORY
            call    zde_put8

            glo     r7
            ani     $1f
            plo     rc
            ldi     ZDI_OPCODE
            call    zde_put8

            glo     r7
            ani     $40
            lbz     zdlf_op0_small
            ldi     2
            lbr     zdlf_op0_have
zdlf_op0_small:
            ldi     1
zdlf_op0_have:
            plo     rc
            ldi     ZDI_OPERAND_TYPES
            call    zde_put8

            glo     r7
            ani     $20
            lbz     zdlf_op1_small
            ldi     2
            lbr     zdlf_op1_have
zdlf_op1_small:
            ldi     1
zdlf_op1_have:
            plo     rc
            ldi     ZDI_OPERAND_TYPES+1
            call    zde_put8

            ldi     2
            plo     rc
            ldi     ZDI_OPERAND_COUNT
            call    zde_put8

; ---- read each operand's value, per its already-written type ----
zdi_read_operands:
            mov     rb, zde_opidx
            ldi     0
            str     rb                  ; zde_opidx = 0 (reused: the
                                        ; type-count loop above, if it
                                        ; ran, is long done)

zdro_loop:
            ldi     ZDI_OPERAND_COUNT
            call    zde_get8            ; d = operand_count
            str     r2
            mov     rb, zde_opidx
            ldn     rb                  ; d = opidx
            sm                          ; d = opidx - operand_count
            lbdf    zdro_done           ; opidx >= operand_count: done

            mov     rb, zde_opidx
            ldn     rb
            adi     ZDI_OPERAND_TYPES
            call    zde_get8            ; d = operand_types[opidx]
            lbz     zdro_large          ; 0 = large (word) operand

            call    zde_read_byte       ; small/variable: one byte,
                                        ; zero-extended to a word
            lbdf    zdi_error
            plo     rc
            ldi     0
            phi     rc
            lbr     zdro_have_operand

zdro_large:
            call    zde_read_word       ; rc = word, big-endian
            lbdf    zdi_error

zdro_have_operand:
            mov     rb, zde_opidx
            ldn     rb
            shl                         ; d = opidx * 2
            adi     ZDI_OPERANDS
            call    zde_put16           ; operands[opidx] = rc

            mov     rb, zde_opidx
            ldn     rb
            adi     1
            str     rb                  ; zde_opidx += 1
            lbr     zdro_loop

; ---- shape lookup: category (rc.0) and opcode (rc.1) both survive
; the two zde_get8 calls that fetch them (rc is untouched by
; zde_fieldptr, unlike r8/r9/rf); once the table entry is found, the
; shape byte itself moves to rb.0, which survives the three zde_put8
; calls below the same way (rb is untouched too) -- rc is free again
; at that point, reused to hold each flag's 0/1 value in turn ----
zdro_done:
            ldi     ZDI_CATEGORY
            call    zde_get8
            plo     rc

            ldi     ZDI_OPCODE
            call    zde_get8
            phi     rc

            glo     rc
            xri     ZDI_CAT_0OP
            lbz     zdi_shape_0op
            glo     rc
            xri     ZDI_CAT_1OP
            lbz     zdi_shape_1op
            glo     rc
            xri     ZDI_CAT_2OP
            lbz     zdi_shape_2op
            lbr     zdi_shape_var

zdi_shape_0op:
            mov     r8, zde_shape_0op_table
            lbr     zdi_shape_index
zdi_shape_1op:
            mov     r8, zde_shape_1op_table
            lbr     zdi_shape_index
zdi_shape_2op:
            mov     r8, zde_shape_2op_table
            lbr     zdi_shape_index
zdi_shape_var:
            mov     r8, zde_shape_var_table

zdi_shape_index:
            ghi     rc                  ; d = opcode
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:opcode
            add16   r8, r9              ; r8 = table + opcode
            ldn     r8                  ; d = shape byte
            plo     rb                  ; rb.0 = shape byte

            glo     rb
            ani     1
            plo     rc
            ldi     ZDI_STORES
            call    zde_put8            ; instr.stores = shape & 1

            glo     rb
            ani     2
            lbz     zdi_not_branches
            ldi     1
            lbr     zdi_have_branches
zdi_not_branches:
            ldi     0
zdi_have_branches:
            plo     rc
            ldi     ZDI_BRANCHES
            call    zde_put8            ; instr.branches = (shape>>1)&1

            glo     rb
            ani     4
            lbz     zdi_not_text
            ldi     1
            lbr     zdi_have_text
zdi_not_text:
            ldi     0
zdi_have_text:
            plo     rc
            ldi     ZDI_HAS_TEXT
            call    zde_put8            ; instr.has_text = (shape>>2)&1

; ---- conditional store/branch/text reads, per the flags just
; written (re-fetched from the buffer rather than carried in a
; register, since every one of these can call zde_read_byte, which
; clobbers r8/r9/rb/rf) ----
            ldi     ZDI_STORES
            call    zde_get8
            lbz     zdi_no_store
            call    zde_read_byte
            lbdf    zdi_error
            plo     rc
            ldi     ZDI_STORE_VARIABLE
            call    zde_put8
zdi_no_store:

            ldi     ZDI_BRANCHES
            call    zde_get8
            lbz     zdi_no_branch
            call    zde_read_byte       ; d = branch1
            lbdf    zdi_error
            plo     r7                  ; r7.0 = branch1 -- r7 survives
                                        ; both zde_read_byte and the
                                        ; zde_put8 calls below

            glo     r7
            ani     $80
            lbz     zdbr_on_false
            ldi     1
            lbr     zdbr_have_on_true
zdbr_on_false:
            ldi     0
zdbr_have_on_true:
            plo     rc
            ldi     ZDI_BRANCH_ON_TRUE
            call    zde_put8

            glo     r7
            ani     $40
            lbz     zdbr_two_byte

            glo     r7
            ani     $3f
            plo     rc
            ldi     0
            phi     rc                  ; single-byte form: offset is
                                        ; the unsigned 6-bit value,
                                        ; always >= 0
            ldi     ZDI_BRANCH_OFFSET
            call    zde_put16
            lbr     zdi_no_branch

zdbr_two_byte:
            call    zde_read_byte       ; d = branch2
            lbdf    zdi_error
            plo     rc                  ; rc.0 = branch2 -- no call
                                        ; happens before it's combined
                                        ; with r7.0 below

            glo     r7
            ani     $3f
            phi     rc                  ; rc = (branch1&$3f):branch2,
                                        ; the raw unsigned 14-bit value

            ghi     rc
            ani     $20
            lbz     zdbr_offset_ready   ; bit 13 clear: value is
                                        ; already the correct signed
                                        ; offset (0..8191)
            sub16   rc, $4000           ; bit 13 set: sign-extend by
                                        ; the same rule as int16_t
                                        ; (offset -= 0x4000)
zdbr_offset_ready:
            ldi     ZDI_BRANCH_OFFSET
            call    zde_put16
zdi_no_branch:

            ldi     ZDI_HAS_TEXT
            call    zde_get8
            lbz     zdi_finalize

zdht_loop:
            call    zde_read_word       ; rc = word
            lbdf    zdi_error
            ghi     rc
            ani     $80
            lbz     zdht_loop           ; end-of-string bit (word's
                                        ; top bit) not set: keep going

; ---- instr.length = cursor(rd) - addr; instr.addr = addr (both
; written here, from the stash made at entry, now that rd holds the
; final cursor position) ----
zdi_finalize:
            mov     r8, zde_addr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = the original addr

            mov     r7, r9              ; r7 = addr, stashed -- zde_put16
                                        ; (via zde_fieldptr) clobbers
                                        ; r8/r9/rf, so r9 itself does
                                        ; NOT survive the call below;
                                        ; r7 does

            mov     r8, rd
            sub16   r8, r9              ; r8 = cursor - addr = length
            mov     rc, r8
            ldi     ZDI_LENGTH
            call    zde_put16

            mov     rc, r7
            ldi     ZDI_ADDR
            call    zde_put16

            clc
            rtn

zdi_error:
            stc
            rtn
            endp

; zde_read_byte (internal): reads the byte at the cursor (rd) into d,
; advancing the cursor by one. DF=1 if the address is non-resident
; (propagated from zmread). Clobbers r8/r9/rb/rf (zmread's own
; footprint); rd survives (zmread doesn't modify its address
; argument), and neither does d (inc doesn't touch it). This depended
; on a real fix in zmread's own cache-fallback path (lib/zmem.asm):
; it used to clobber rd there (reusing it to hold zcread's high-word
; argument) while resident reads left it alone, so any fetch that
; happened to land in cache-backed memory would silently corrupt this
; cursor instead of just advancing it -- never caught because every
; existing diag uses a fully-resident zminit region.
            proc    zde_read_byte
            call    zmread
            lbdf    zrb_fail
            inc     rd
            clc
            rtn
zrb_fail:
            mov     rb, zde_fail_addr
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb                  ; zde_fail_addr = rd (the exact
                                        ; cursor address the failing
                                        ; zmread call was given -- rd is
                                        ; NOT advanced on this path)
            stc
            rtn
            endp

; zde_read_word (internal): reads a big-endian word at the cursor into
; rc, advancing the cursor by two. DF=1 on failure (either byte).
            proc    zde_read_word
            call    zde_read_byte
            lbdf    zrw_fail
            phi     rc
            call    zde_read_byte
            lbdf    zrw_fail
            plo     rc
            clc
            rtn
zrw_fail:
            stc
            rtn
            endp

; zde_fieldptr (internal): d = byte offset into the instruction buffer
; (set immediately before the call). Returns rf = zde_instr + offset.
; Clobbers r8/r9/rf/d.
            proc    zde_fieldptr
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:offset
            mov     rf, zde_instr
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = the buffer's own address
                                        ; (the VALUE stored at zde_instr,
                                        ; not zde_instr's own address)
            mov     rf, r8
            add16   rf, r9
            clc
            rtn
            endp

; zde_get8 (internal): d = byte offset (set immediately before the
; call). Returns d = the byte at that offset in the instruction
; buffer. Clobbers r8/r9/rf.
            proc    zde_get8
            call    zde_fieldptr
            ldn     rf
            clc
            rtn
            endp

; zde_put8 (internal): d = byte offset, rc.0 = value (both set
; immediately before the call). Writes rc.0 to that offset. Clobbers
; r8/r9/rf.
            proc    zde_put8
            call    zde_fieldptr
            glo     rc
            str     rf
            clc
            rtn
            endp

; zde_put16 (internal): d = byte offset, rc = value, big-endian (both
; set immediately before the call). Writes rc to that offset and the
; next byte. Clobbers r8/r9/rf.
            proc    zde_put16
            call    zde_fieldptr
            ghi     rc
            str     rf
            inc     rf
            glo     rc
            str     rf
            clc
            rtn
            endp

            proc    _zdecode_data
zde_addr:       dw      0
zde_instr:      dw      0
zde_opidx:      db      0
zde_fail_addr:  dw      0       ; the exact cursor address zde_read_byte
                                ; was reading when it hit a zmread
                                ; failure -- may be past zde_addr, since
                                ; decode can fail partway through an
                                ; otherwise-valid instruction (operand,
                                ; store, branch, or inline-text byte);
                                ; see this file's own zde_read_byte
                public  zde_addr
                public  zde_instr
                public  zde_opidx
                public  zde_fail_addr
            endp

; Packed one byte per opcode: bit 0 = stores a result, bit 1 =
; branches, bit 2 = carries an inline packed string (0OP print/
; print_ret only). Shape, not semantics -- an opcode this table
; doesn't recognize (unassigned in V3, or a later version's) is all
; zero, matching host/decode.c's own tables exactly, entry for entry.
            proc    _zdecode_shapes
zde_shape_2op_table:
                db      0               ;  0
                db      2               ;  1 je
                db      2               ;  2 jl
                db      2               ;  3 jg
                db      2               ;  4 dec_chk
                db      2               ;  5 inc_chk
                db      2               ;  6 jin
                db      2               ;  7 test
                db      1               ;  8 or
                db      1               ;  9 and
                db      2               ; 10 test_attr
                db      0               ; 11 set_attr
                db      0               ; 12 clear_attr
                db      0               ; 13 store
                db      0               ; 14 insert_obj
                db      1               ; 15 loadw
                db      1               ; 16 loadb
                db      1               ; 17 get_prop
                db      1               ; 18 get_prop_addr
                db      1               ; 19 get_next_prop
                db      1               ; 20 add
                db      1               ; 21 sub
                db      1               ; 22 mul
                db      1               ; 23 div
                db      1               ; 24 mod
                db      0               ; 25 (not in V3)
                db      0               ; 26
                db      0               ; 27
                db      0               ; 28
                db      0               ; 29
                db      0               ; 30
                db      0               ; 31

zde_shape_1op_table:
                db      2               ;  0 jz
                db      3               ;  1 get_sibling
                db      3               ;  2 get_child
                db      1               ;  3 get_parent
                db      1               ;  4 get_prop_len
                db      0               ;  5 inc
                db      0               ;  6 dec
                db      0               ;  7 print_addr
                db      0               ;  8 (not in V3)
                db      0               ;  9 remove_obj
                db      0               ; 10 print_obj
                db      0               ; 11 ret
                db      0               ; 12 jump
                db      0               ; 13 print_paddr
                db      1               ; 14 load
                db      1               ; 15 not

zde_shape_0op_table:
                db      0               ;  0 rtrue
                db      0               ;  1 rfalse
                db      4               ;  2 print
                db      4               ;  3 print_ret
                db      0               ;  4 nop
                db      2               ;  5 save
                db      2               ;  6 restore
                db      0               ;  7 restart
                db      0               ;  8 ret_popped
                db      0               ;  9 pop
                db      0               ; 10 quit
                db      0               ; 11 new_line
                db      0               ; 12 show_status
                db      2               ; 13 verify
                db      0               ; 14 (not in V3)
                db      0               ; 15 (not in V3)

zde_shape_var_table:
                db      1               ;  0 call
                db      0               ;  1 storew
                db      0               ;  2 storeb
                db      0               ;  3 put_prop
                db      0               ;  4 sread
                db      0               ;  5 print_char
                db      0               ;  6 print_num
                db      1               ;  7 random
                db      0               ;  8 push
                db      0               ;  9 pull
                db      0               ; 10 split_window
                db      0               ; 11 set_window
                db      0               ; 12 (not in V3)
                db      0               ; 13
                db      0               ; 14
                db      0               ; 15
                db      0               ; 16
                db      0               ; 17
                db      0               ; 18
                db      0               ; 19 output_stream
                db      0               ; 20 input_stream
                db      0               ; 21 (not in V3)
                db      0               ; 22
                db      0               ; 23
                db      0               ; 24
                db      0               ; 25
                db      0               ; 26
                db      0               ; 27
                db      0               ; 28
                db      0               ; 29
                db      0               ; 30
                db      0               ; 31

                public  zde_shape_2op_table
                public  zde_shape_1op_table
                public  zde_shape_0op_table
                public  zde_shape_var_table
            endp
