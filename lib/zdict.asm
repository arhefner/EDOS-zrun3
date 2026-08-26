;
; zdict.asm - V3 dictionary word encoding and lookup
;
; Mirrors host/ztext.c's ztext_encode and host/dictionary.c. zdict_init
; parses a dictionary header once; zdict_encode/zdict_lookup/
; zdict_find_word take it from there. No calls happen inside
; zdict_encode or zdict_lookup, so their own register use doesn't need
; to dodge anything the way zobj.asm's does -- only zdict_find_word
; (which calls both) needs the usual care.
;
; Register budget matches zobj.asm/zprop.asm: only R7-RD and RF, no
; R1, no RE.
;

#include    include/opcodes.def

            extrn   zdi_entries
            extrn   zdi_entry_length
            extrn   zdi_entry_count
            extrn   zde_zchars
            extrn   zde_output
            extrn   zde_punct_table
            extrn   zdf_scratch

            extrn   zdict_encode
            extrn   zdict_lookup

; zdict_init: RD = dictionary address. Parses the separator table
; (skipped over, not otherwise used here), entry length, and entry
; count, and remembers where the entries themselves start.
            proc    zdict_init
            mov     r8, rd              ; r8 = dictionary address
            ldn     r8                  ; d = separator count
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:separator count
            mov     rf, r8
            inc     rf
            add16   rf, r9              ; rf = &entry_length

            ldn     rf                  ; d = entry_length
            plo     r7                  ; stash it -- mov clobbers D
            mov     rb, zdi_entry_length
            glo     r7
            str     rb

            inc     rf                  ; rf = &entry_count
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = entry_count (raw, signed)
            mov     rb, zdi_entry_count
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb

            inc     rf                  ; rf = entries_addr
            mov     rb, zdi_entries
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            clc
            rtn
            endp

; zdict_encode: RD = text address, RF = output buffer address (4
; bytes), D = length in characters (set immediately before the call).
; Encodes up to a dictionary word's worth of lowercase/uppercase
; letters, digits, and the standard A2 punctuation set; longer input
; is truncated at a z-character boundary, matching
; host/ztext.c's ztext_encode. DF=1 only for a character that can't be
; encoded at all.
            proc    zdict_encode
            plo     r8                  ; r8.0 = remaining length --
                                        ; captured before anything below
                                        ; can clobber D
            mov     r9, rd              ; r9 = text cursor

            mov     rd, zde_output
            ghi     rf
            str     rd
            inc     rd
            glo     rf
            str     rd                  ; zde_output = output buffer

            mov     ra, zde_zchars      ; ra = zchar fill pointer
            mov     rf, zde_zchars
            ldi     5                   ; the standard V3 padding
                                        ; z-character
            str     rf
            inc     rf
            str     rf
            inc     rf
            str     rf
            inc     rf
            str     rf
            inc     rf
            str     rf
            inc     rf
            str     rf                  ; zde_zchars[0..5] = 5,5,5,5,5,5

zde_loop:
            glo     r8
            lbz     zde_pack            ; no characters left: pack
            lda     r9                  ; d = next character; r9++
            dec     r8
            plo     rc                  ; rc.0 = c

            xri     ' '
            lbz     zde_space

            glo     rc
            smi     'a'
            lbnf    zde_try_upper       ; c < 'a'
            glo     rc
            smi     'z'+1
            lbdf    zde_try_upper       ; c > 'z'
            glo     rc
            smi     'a'
            adi     6
            plo     rd                  ; rd.0 = code
            ldi     0
            plo     r7                  ; r7.0 = shift (none)
            lbr     zde_have_code

zde_try_upper:
            glo     rc
            smi     'A'
            lbnf    zde_try_punct       ; c < 'A'
            glo     rc
            smi     'Z'+1
            lbdf    zde_try_punct       ; c > 'Z'
            glo     rc
            smi     'A'
            adi     6
            plo     rd
            ldi     4                   ; shift to A1
            plo     r7
            lbr     zde_have_code

zde_try_punct:
            mov     rb, zde_punct_table
            mov     rf, zde_punct_table+24
zde_punct_loop:
            glo     rb
            str     r2
            glo     rf
            xor
            lbnz    zde_punct_continue
            ghi     rb
            str     r2
            ghi     rf
            xor
            lbz     zde_unencodable     ; rb == rf: table exhausted
zde_punct_continue:
            ldn     rb
            str     r2
            glo     rc
            xor
            lbz     zde_punct_found
            inc     rb
            lbr     zde_punct_loop

zde_punct_found:
            mov     rd, rb
            sub16   rd, zde_punct_table ; rd = position in the table
            glo     rd
            adi     7                   ; d = 6 + 1 + position
            plo     rd
            ldi     5                   ; shift to A2
            plo     r7
            lbr     zde_have_code

zde_space:
            ldi     0
            plo     rd                  ; rd.0 = code (space)
            ldi     0
            plo     r7                  ; r7.0 = shift (none)

zde_have_code:
            mov     rb, ra
            inc     rb                  ; +1 for the code itself
            glo     r7
            lbz     zde_check_fit
            inc     rb                  ; shift != 0: one more slot
zde_check_fit:
            mov     rf, zde_zchars+6
            mov     rc, rb
            sub16   rc, rf
            lbdf    zde_pack            ; rb >= end: doesn't fit --
                                        ; stop consuming input here
            glo     r7
            lbz     zde_write_code
            glo     r7
            str     ra
            inc     ra
zde_write_code:
            glo     rd
            str     ra
            inc     ra
            lbr     zde_loop

zde_unencodable:
            stc
            rtn

zde_pack:
            mov     rf, zde_output
            lda     rf
            phi     rb
            ldn     rf
            plo     rb                  ; rb = output buffer address

            mov     rf, zde_zchars
            ldn     rf
            plo     r8
            ldi     0
            phi     r8                  ; r8 = 0:z0
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8                  ; r8 = z0 << 5

            inc     rf
            ldn     rf                  ; d = z1
            plo     r9
            ldi     0
            phi     r9
            add16   r8, r9              ; r8 = (z0<<5) + z1
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8                  ; r8 = (z0<<10) | (z1<<5)

            inc     rf
            ldn     rf                  ; d = z2
            plo     r9
            ldi     0
            phi     r9
            add16   r8, r9              ; r8 = word0

            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb
            inc     rb                  ; output[0..1] = word0

            inc     rf
            ldn     rf                  ; d = z3
            plo     r8
            ldi     0
            phi     r8
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8

            inc     rf
            ldn     rf                  ; d = z4
            plo     r9
            ldi     0
            phi     r9
            add16   r8, r9
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8
            shl16   r8

            inc     rf
            ldn     rf                  ; d = z5
            plo     r9
            ldi     0
            phi     r9
            add16   r8, r9              ; r8 = word1's low 15 bits

            ghi     r8
            ori     $80                 ; set the end-of-string bit
            str     rb
            inc     rb
            glo     r8
            str     rb                  ; output[2..3] = word1

            clc
            rtn
            endp

; zdict_lookup: RD = encoded word address (4 bytes). Returns RF = the
; matching entry's address, or 0 if none matches.
            proc    zdict_lookup
            mov     r9, rd              ; r9 = encoded text address
            mov     rb, zdi_entries
            lda     rb
            phi     r7
            ldn     rb
            plo     r7                  ; r7 = current entry (cursor)

            mov     rb, zdi_entry_count
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; r8 = entry_count (raw)
            ghi     r8
            ani     $80
            lbz     zdl_loop
            mov     rc, 0
            sub16   rc, r8
            mov     r8, rc              ; negative (unsorted): use the
                                        ; magnitude -- correctness here
                                        ; doesn't depend on sort order

zdl_loop:
            glo     r8
            lbnz    zdl_check
            ghi     r8
            lbnz    zdl_check
            lbr     zdl_notfound

zdl_check:
            mov     rf, r7
            mov     rd, r9
            ldn     rf
            str     r2
            ldn     rd
            xor
            lbnz    zdl_next
            inc     rf
            inc     rd
            ldn     rf
            str     r2
            ldn     rd
            xor
            lbnz    zdl_next
            inc     rf
            inc     rd
            ldn     rf
            str     r2
            ldn     rd
            xor
            lbnz    zdl_next
            inc     rf
            inc     rd
            ldn     rf
            str     r2
            ldn     rd
            xor
            lbnz    zdl_next
            mov     rf, r7              ; all 4 bytes matched
            clc
            rtn

zdl_next:
            mov     rf, zdi_entry_length
            ldn     rf
            plo     rc
            ldi     0
            phi     rc
            mov     rf, r7
            add16   rf, rc
            mov     r7, rf              ; r7 = next entry address
            dec     r8
            lbr     zdl_loop

zdl_notfound:
            mov     rf, 0
            clc
            rtn
            endp

; zdict_find_word: RD = text address, D = length (set immediately
; before the call). Encodes and looks up in one step; returns RF = the
; matching entry's address (0 if none), DF=1 if the text couldn't be
; encoded at all.
            proc    zdict_find_word
            plo     r9                  ; r9.0 = length
            mov     r8, rd              ; r8 = text address
            mov     rf, zdf_scratch
            mov     rd, r8
            glo     r9
            call    zdict_encode
            lbdf    zdf_error
            mov     rd, zdf_scratch
            call    zdict_lookup
            rtn

zdf_error:
            mov     rf, 0
            stc
            rtn
            endp

            proc    _zdict_data
zdi_entries:        dw      0
zdi_entry_length:    db      0
zdi_entry_count:     dw      0
zde_zchars:          ds      6
zde_output:          dw      0
zdf_scratch:         ds      4
zde_punct_table:     db      "0123456789.,!?_#'",34,"/",92,"-:()"
                public  zdi_entries
                public  zdi_entry_length
                public  zdi_entry_count
                public  zde_zchars
                public  zde_output
                public  zdf_scratch
                public  zde_punct_table
            endp
