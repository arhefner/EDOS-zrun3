;
; zobj.asm - V3 object tree and attribute access
;
; Mirrors host/objects.c. zobj_init records the object table's base
; address once; every other routine takes an object number in RD and
; trusts it is in range (1-255) and, for tree-walking routines, that
; the tree itself is consistent -- callers must validate a Z-machine
; object operand before reaching these primitives, the same trust
; boundary zmem.asm/zstack.asm already assume for their own address
; arguments.
;
; Only R7-RD and RF are ever used as scratch here (no R0-R2 beyond R2's
; existing role as SUB16/ADD16's own transient pointer, no R1, no RE,
; R3-R6 belong to SCRT). zobj_entry -- called by nearly everything --
; is deliberately narrowed to clobber only R8/RD/RF/D, which leaves
; R7/R9/RA/RB/RC free for callers to hold values across it. zobj_remove
; alone needs four such values (object/parent/cursor/sibling) and uses
; RA/RC/R7/RB for them; nothing it calls touches any of the four.
; zobj_set_parent/set_sibling/set_child/zobj_attr_locate use R9 for
; their own incoming byte, which is therefore off limits to any caller
; that needs a value to survive one of *those* calls -- zobj_insert's
; "destination" does, so it goes through the zoi_destination scratch
; byte instead of a register.
;

#include    include/opcodes.def

            extrn   zobase

            extrn   zobj_entry
            extrn   zobj_get_parent
            extrn   zobj_get_sibling
            extrn   zobj_get_child
            extrn   zobj_set_parent
            extrn   zobj_set_sibling
            extrn   zobj_set_child
            extrn   zobj_attr_locate
            extrn   zobj_remove
            extrn   zobj_prop_table_addr

            extrn   zoi_destination

OBJ_ENTRY_SIZE:         equ     9
OBJ_PROP_DEFAULTS_SIZE: equ     62

; zobj_init: RD = object table address.
            proc    zobj_init
            mov     rb, zobase
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            clc
            rtn
            endp

; zobj_entry: RD = object number. Returns RF = entry address. Clobbers
; only R8/RD/RF/D -- R9/RA/RB/RC/R7 all survive a call to this.
            proc    zobj_entry
            mov     r8, rd
            sub16   r8, 1               ; r8 = object - 1
            mov     rd, r8              ; rd = a second copy -- the
                                        ; caller's object number is no
                                        ; longer needed, and this multiply
                                        ; needs one register to shift and
                                        ; another to hold the addend
            shl16   r8
            shl16   r8
            shl16   r8                  ; r8 = (object-1)*8
            add16   r8, rd              ; r8 = (object-1)*9
            mov     rf, zobase
            lda     rf
            phi     rd                  ; rd = object table base (reusing
            ldn     rf                  ; rd again -- its (object-1) copy
            plo     rd                  ; is no longer needed either)
            mov     rf, rd
            add16   rf, OBJ_PROP_DEFAULTS_SIZE
            add16   rf, r8              ; rf = entry address
            clc
            rtn
            endp

; zobj_get_parent: RD = object. Returns D = parent (0 if none).
            proc    zobj_get_parent
            call    zobj_entry
            add16   rf, 4
            ldn     rf
            clc
            rtn
            endp

; zobj_get_sibling: RD = object. Returns D = sibling (0 if none).
            proc    zobj_get_sibling
            call    zobj_entry
            add16   rf, 5
            ldn     rf
            clc
            rtn
            endp

; zobj_get_child: RD = object. Returns D = child (0 if none).
            proc    zobj_get_child
            call    zobj_entry
            add16   rf, 6
            ldn     rf
            clc
            rtn
            endp

; zobj_set_parent: RD = object, D = new parent (set by the caller
; immediately before the call).
            proc    zobj_set_parent
            plo     r9                  ; stash the value out of D --
                                        ; zobj_entry leaves R9 alone
            call    zobj_entry
            add16   rf, 4
            glo     r9
            str     rf
            clc
            rtn
            endp

; zobj_set_sibling: RD = object, D = new sibling.
            proc    zobj_set_sibling
            plo     r9
            call    zobj_entry
            add16   rf, 5
            glo     r9
            str     rf
            clc
            rtn
            endp

; zobj_set_child: RD = object, D = new child.
            proc    zobj_set_child
            plo     r9
            call    zobj_entry
            add16   rf, 6
            glo     r9
            str     rf
            clc
            rtn
            endp

; zobj_attr_locate (internal): RD = object, D = attribute (0-31, set
; immediately before the call). Returns RF = the attribute's byte
; address, RC.0 = its bit mask.
            proc    zobj_attr_locate
            plo     r9                  ; r9.0 = attribute
            call    zobj_entry          ; rf = entry address
            ldi     0
            phi     r9                  ; r9 = 0:attribute
            mov     r8, r9
            shr16   r8
            shr16   r8
            shr16   r8                  ; r8 = attribute >> 3 (byte 0-3)
            add16   rf, r8              ; rf = the attribute's byte
            glo     r9
            ani     $07                 ; d = attribute & 7 (bit index
                                        ; from the top of the byte)
            plo     r8
            ldi     $80
            plo     rc                  ; rc.0 = mask, starts at bit 0
zal_shift:
            glo     r8
            lbz     zal_done
            dec     r8
            glo     rc
            shr
            plo     rc
            lbr     zal_shift
zal_done:
            clc
            rtn
            endp

; zobj_test_attr: RD = object, D = attribute (0-31). Returns DF=1 if
; the attribute is set, DF=0 if clear.
            proc    zobj_test_attr
            call    zobj_attr_locate
            ldn     rf
            str     r2
            glo     rc
            and
            lbz     zta_clear
            stc
            rtn
zta_clear:
            clc
            rtn
            endp

; zobj_set_attr: RD = object, D = attribute (0-31).
            proc    zobj_set_attr
            call    zobj_attr_locate
            ldn     rf
            str     r2
            glo     rc
            or
            str     rf
            clc
            rtn
            endp

; zobj_clear_attr: RD = object, D = attribute (0-31).
            proc    zobj_clear_attr
            call    zobj_attr_locate
            glo     rc
            not                         ; d = ~mask
            str     r2
            ldn     rf
            and
            str     rf
            clc
            rtn
            endp

; zobj_remove: RD = object. Detaches it from the tree (unlinks it from
; its parent's child list); a no-op if it already has no parent. DF=1
; if the parent's child list never actually contained the object (a
; caller/tree-consistency bug).
;
; Uses RA (object), RC (parent), R7 (cursor), and RB (sibling) as
; persistent state -- none of zobj_get_*/zobj_set_* touch any of the
; four, so they need no memory-backed scratch, unlike zobj_insert's
; "destination" below.
            proc    zobj_remove
            mov     ra, rd              ; ra = object
            call    zobj_get_parent     ; d = parent
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:parent
            glo     rc
            lbnz    zor_haveparent
            clc
            rtn                         ; no parent: already detached

zor_haveparent:
            mov     rd, ra
            call    zobj_get_sibling    ; d = sibling
            plo     rb
            ldi     0
            phi     rb                  ; rb = 0:sibling

            mov     rd, rc
            call    zobj_get_child      ; d = parent's child
            plo     r7
            ldi     0
            phi     r7                  ; r7 = 0:cursor
            glo     r7
            str     r2
            glo     ra
            xor
            lbnz    zor_walk
            ; parent's child IS object: sibling becomes the new child
            mov     rd, rc
            glo     rb
            call    zobj_set_child      ; set_child(parent, sibling)
            lbr     zor_relink

zor_walk:
            glo     r7
            lbz     zor_corrupt
            mov     rd, r7
            call    zobj_get_sibling    ; d = sibling(cursor) ("next")
            str     r2
            glo     ra
            xor
            lbnz    zor_advance
            mov     rd, r7
            glo     rb
            call    zobj_set_sibling    ; set_sibling(cursor, sibling)
            lbr     zor_relink

zor_advance:
            ldn     r2                  ; recover "next" -- the xor
                                        ; above only read M(R2), never
                                        ; wrote it
            plo     r7
            ldi     0
            phi     r7
            lbr     zor_walk

zor_relink:
            mov     rd, ra
            ldi     0
            call    zobj_set_parent     ; set_parent(object, 0)
            mov     rd, ra
            ldi     0
            call    zobj_set_sibling    ; set_sibling(object, 0)
            clc
            rtn

zor_corrupt:
            stc
            rtn
            endp

; zobj_insert: RD = object, D = destination (set immediately before
; the call). Detaches object from wherever it currently is, then
; attaches it as destination's new first child.
;
; "destination" is kept in the zoi_destination scratch byte, not a
; register: zobj_remove below clobbers R7/R9/RA/RB/RC (it uses all
; four for its own state), so nothing survives that call except RD/D
; at proc entry (already spent) and memory.
            proc    zobj_insert
            plo     r9                  ; r9.0 = destination
            mov     ra, rd              ; ra = object
            mov     rf, zoi_destination
            glo     r9
            str     rf                  ; zoi_destination = destination
            call    zobj_remove         ; rd is still = object
            mov     rf, zoi_destination
            ldn     rf
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:destination -- safe to
                                        ; keep in RC from here on, since
                                        ; nothing called below touches it
            mov     rd, rc
            call    zobj_get_child      ; d = destination's former child
            plo     r9
            mov     rd, ra
            glo     r9
            call    zobj_set_sibling    ; set_sibling(object, former_child)
            mov     rd, rc
            glo     ra
            call    zobj_set_child      ; set_child(destination, object)
            mov     rd, ra
            glo     rc
            call    zobj_set_parent     ; set_parent(object, destination)
            clc
            rtn
            endp

; zobj_prop_table_addr: RD = object. Returns RF = property table
; address.
            proc    zobj_prop_table_addr
            call    zobj_entry
            add16   rf, 7
            lda     rf
            phi     r8
            ldn     rf
            plo     r8
            mov     rf, r8
            clc
            rtn
            endp

; zobj_short_name: RD = object. Returns RF = address of the packed
; short-name text (ready for ztext_decode), RC = its length in bytes.
            proc    zobj_short_name
            call    zobj_prop_table_addr    ; rf = property table addr
            ldn     rf
            plo     rc
            ldi     0
            phi     rc
            shl16   rc                       ; rc = word_count * 2
            inc     rf                        ; rf = table+1 (text start)
            clc
            rtn
            endp

            proc    _zobj_data
zobase:             dw      0
zoi_destination:    db      0
                public  zobase
                public  zoi_destination
            endp
