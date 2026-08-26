;
; zprop.asm - V3 property table access
;
; Mirrors host/properties.c, built on zobj.asm's object tree access
; (zobj_short_name locates where an object's property list starts;
; zobase gives the property-defaults table's base, which is simply
; the object table's own base -- the defaults occupy its first 62
; bytes). Trusts its object/property arguments are in range, the same
; boundary zobj.asm's own routines assume.
;
; Register budget matches zobj.asm: only R7-RD and RF are ever used as
; scratch (no R1, no RE).
;

#include    include/opcodes.def

            extrn   zobj_short_name
            extrn   zobase

            extrn   zprop_get_addr
            extrn   zprop_get_len

; zprop_get_addr: RD = object, D = property (set immediately before
; the call, 1-31). Returns RF = the property's data address, or 0 if
; the object doesn't have that property.
            proc    zprop_get_addr
            plo     r9                  ; r9.0 = property -- survives
                                        ; the call below (zobj_short_name
                                        ; clobbers R8/RD/RF/RC/D, not R9)
            call    zobj_short_name     ; rf = short-name addr, rc =
                                        ; short-name length
            add16   rf, rc              ; rf = start of the property list
zpga_loop:
            ldn     rf                  ; d = size byte (0 = end of list)
            lbz     zpga_notfound
            plo     r8                  ; r8.0 = size byte (needed twice
                                        ; below: property number, length)
            ani     $1f                 ; d = this entry's property number
            str     r2
            glo     r9
            xor
            lbz     zpga_found
            ; not a match: skip this entry's data and continue
            glo     r8
            shr
            shr
            shr
            shr
            shr                         ; d = length - 1 (top 3 bits)
            adi     1                   ; d = length (1-8)
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:length
            inc     rf                  ; rf = this entry's data address
            add16   rf, rc              ; rf = next entry's address
            lbr     zpga_loop

zpga_found:
            inc     rf                  ; rf = this entry's data address
            clc
            rtn

zpga_notfound:
            mov     rf, 0
            clc
            rtn
            endp

; zprop_get_len: RD = address (as returned by zprop_get_addr; 0 = no
; property). Returns D = length in bytes (0 for address 0).
            proc    zprop_get_len
            glo     rd
            lbnz    zpgl_have_addr
            ghi     rd
            lbnz    zpgl_have_addr
            ldi     0
            clc
            rtn

zpgl_have_addr:
            mov     rf, rd
            dec     rf                  ; rf = the size byte just before
                                        ; the data
            ldn     rf
            shr
            shr
            shr
            shr
            shr                         ; d = length - 1
            adi     1                   ; d = length
            clc
            rtn
            endp

; zprop_get: RD = object, D = property. Returns RF = value, falling
; back to the property-defaults table when the object doesn't have the
; property itself. A property longer than 2 bytes yields its first
; word, matching host/properties.c's prop_get.
            proc    zprop_get
            plo     r7                  ; r7.0 = property -- survives
                                        ; the call below (zprop_get_addr
                                        ; clobbers R8/R9/RC/RF/RD/D, not
                                        ; R7)
            call    zprop_get_addr      ; rf = data address (0 if absent)
            glo     rf
            lbnz    zpg_have_addr
            ghi     rf
            lbnz    zpg_have_addr

            ; not present: read the property-defaults table instead
            mov     rb, zobase
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; r8 = object table base (== the
                                        ; property-defaults table base)
            glo     r7
            smi     1                   ; d = property - 1
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:(property-1)
            shl16   r9                  ; r9 = (property-1)*2
            mov     rf, r8
            add16   rf, r9              ; rf = &defaults[property-1]
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = defaults[property-1]
            mov     rf, r9
            clc
            rtn

zpg_have_addr:
            mov     r7, rf              ; r7 = addr -- survives the call
                                        ; below (property is no longer
                                        ; needed once addr is known)
            mov     rd, rf
            call    zprop_get_len       ; d = length
            xri     1
            lbnz    zpg_word
            ; length == 1: zero-extended byte
            mov     rf, r7
            ldn     rf
            plo     rf
            ldi     0
            phi     rf
            clc
            rtn

zpg_word:
            mov     rf, r7
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, r9
            clc
            rtn
            endp

; zprop_get_next: RD = object, D = property (0 = "the object's first
; property"). Returns D = the next property number (0 = none left),
; DF=1 if `property` wasn't actually one of the object's properties.
            proc    zprop_get_next
            plo     r9                  ; r9.0 = target property
            call    zobj_short_name     ; rf = short-name addr, rc =
                                        ; short-name length
            add16   rf, rc              ; rf = start of the property list
            glo     r9
            lbz     zpgn_first
            ldi     0
            lbr     zpgn_have_flag
zpgn_first:
            ldi     1
zpgn_have_flag:
            plo     r8                  ; r8.0 = "report the next entry
                                        ; we see" flag

zpgn_loop:
            ldn     rf                  ; d = size byte (0 = end of list)
            plo     rc                  ; rc.0 = size byte (needed twice
                                        ; below: property number, length)
            glo     r8
            lbnz    zpgn_report         ; flag set: report whatever is
                                        ; here now, terminator included
                                        ; (masking a 0 size byte reports
                                        ; property 0, "none left")
            glo     rc
            lbz     zpgn_notfound       ; terminator reached without
                                        ; ever finding `property`
            glo     rc
            ani     $1f
            str     r2
            glo     r9
            xor
            lbnz    zpgn_skip
            ldi     1
            plo     r8                  ; found it: the next loop pass
                                        ; reports the entry after this
zpgn_skip:
            glo     rc
            shr
            shr
            shr
            shr
            shr                         ; d = length - 1
            adi     1                   ; d = length
            plo     r7
            ldi     0
            phi     r7                  ; r7 = 0:length
            inc     rf                  ; rf = this entry's data address
            add16   rf, r7              ; rf = next entry's address
            lbr     zpgn_loop

zpgn_report:
            glo     rc
            ani     $1f
            clc
            rtn

zpgn_notfound:
            stc
            rtn
            endp
