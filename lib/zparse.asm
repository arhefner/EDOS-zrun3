;
; zparse.asm - V3 text tokenizer
;
; Mirrors host/parser.c's parser_tokenize, built on zdict.asm
; (zdict_find_word, and zdi_dict_addr for the separator table).
; zparse_init records the text/parse buffer parameters once;
; zparse_tokenize takes it from there.
;
; zdict_find_word (via zdict_encode) touches nearly every register, so
; unlike zobj.asm/zprop.asm/zdict.asm's own internal calls, nothing
; here tries to carry a value in a register across a call -- every
; loop variable (position, word count, parse cursor, word length, word
; start) lives in memory and is reloaded fresh after any call.
;
; Register budget matches the rest of this project: only R7-RD and RF,
; no R1, no RE.
;

#include    include/opcodes.def

            extrn   zdi_dict_addr
            extrn   zdict_find_word

            extrn   zp_text_addr
            extrn   zp_text_length
            extrn   zp_text_offset
            extrn   zp_parse_addr
            extrn   zp_pos
            extrn   zp_word_count
            extrn   zp_parse_cursor
            extrn   zp_start
            extrn   zp_length
            extrn   zp_read_len
            extrn   zp_word_buf

            extrn   zpt_is_separator

; zparse_init: RD = text address, RF = parse buffer address, RC.0 =
; text length, RC.1 = text offset (added to each word's recorded
; position -- 2 for a real text buffer, whose characters start right
; after its 2-byte header).
            proc    zparse_init
            mov     rb, zp_text_addr
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb

            mov     rb, zp_parse_addr
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb

            mov     rb, zp_text_length
            glo     rc
            str     rb

            mov     rb, zp_text_offset
            ghi     rc
            str     rb
            clc
            rtn
            endp

; zpt_is_separator (internal): D = character to test (set immediately
; before the call). Returns DF=1 if it's one of the dictionary's
; separator characters.
            proc    zpt_is_separator
            plo     r7                  ; r7.0 = character
            mov     rb, zdi_dict_addr
            lda     rb
            phi     r8
            ldn     rb
            plo     r8                  ; r8 = dictionary address
            mov     rf, r8
            ldn     rf                  ; d = separator count
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:separator count
            mov     rb, r8
            inc     rb                  ; rb = &separators[0]
zis_loop:
            glo     r9
            lbnz    zis_check
            ghi     r9
            lbnz    zis_check
            clc
            rtn                         ; count exhausted: not a match
zis_check:
            ldn     rb
            str     r2
            glo     r7
            xor
            lbz     zis_yes
            inc     rb
            dec     r9
            lbr     zis_loop
zis_yes:
            stc
            rtn
            endp

; zparse_tokenize: no arguments (uses the state zparse_init recorded).
; Tokenizes the text against the dictionary, writing the standard V3
; parse buffer format (word count, then 4 bytes per word: dictionary
; address, length, position). DF=1 only if a word's text couldn't be
; encoded at all (propagated from zdict_find_word); the parse buffer
; may be partially written in that case, matching host/parser.c's own
; all-or-nothing-per-call contract.
            proc    zparse_tokenize
            mov     rb, zp_pos
            ldi     0
            str     rb
            inc     rb
            str     rb                  ; zp_pos = 0

            mov     rb, zp_word_count
            ldi     0
            str     rb                  ; zp_word_count = 0

            mov     rf, zp_parse_addr
            lda     rf
            phi     r8
            ldn     rf
            plo     r8
            add16   r8, 2               ; r8 = parse_addr + 2
            mov     rb, zp_parse_cursor
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb

zpt_loop:
            mov     rf, zp_pos
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = pos
            mov     rf, zp_text_length
            ldn     rf
            str     r2
            glo     r8
            sm                          ; d = pos - text_length
            lbdf    zpt_done            ; pos >= text_length: done

            mov     rf, zp_parse_addr
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = parse_addr (the value,
                                        ; not the field's own address)
            ldn     r9                  ; d = max_words
            str     r2
            mov     rf, zp_word_count
            ldn     rf                  ; d = word_count
            sm                          ; d = word_count - max_words
            lbdf    zpt_done            ; word_count >= max_words: done

            mov     rf, zp_text_addr
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = text_addr
            add16   r9, r8              ; r9 = text_addr + pos
            ldn     r9                  ; d = c
            xri     ' '
            lbz     zpt_skip_space
            xri     ' '                 ; undo the xor: d = c again
                                        ; (xor is its own inverse)
            plo     r7
            call    zpt_is_separator
            lbdf    zpt_sep_token

; ---- ordinary word: scan forward to the next space/separator ----
            mov     rf, zp_pos
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = pos (reload -- the
                                        ; separator check above just
                                        ; called zpt_is_separator,
                                        ; which clobbers r8)
            mov     rb, zp_start
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb                  ; zp_start = pos
            mov     rf, zp_length
            ldi     0
            str     rf                  ; zp_length = 0

zpt_scan:
            mov     rf, zp_pos
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = pos
            mov     rf, zp_text_length
            ldn     rf
            str     r2
            glo     r8
            sm
            lbdf    zpt_word_done       ; pos >= text_length: word ends

            mov     rf, zp_text_addr
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            add16   r9, r8
            ldn     r9                  ; d = c
            xri     ' '
            lbz     zpt_word_done       ; space: word ends here
            xri     ' '
            plo     r7
            call    zpt_is_separator
            lbdf    zpt_word_done       ; separator: word ends here --
                                        ; it is NOT consumed; the outer
                                        ; loop picks it up next as its
                                        ; own one-character token

            mov     rf, zp_pos
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = pos (reload -- the
                                        ; separator check above called
                                        ; zpt_is_separator again)
            mov     r9, r8
            add16   r9, 1
            mov     rb, zp_pos
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb                  ; zp_pos = pos + 1

            mov     rf, zp_length
            ldn     rf
            adi     1
            str     rf                  ; zp_length += 1
            lbr     zpt_scan

zpt_word_done:
            lbr     zpt_lookup

zpt_sep_token:
            mov     rf, zp_pos
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = pos (reload -- reached
                                        ; via the separator check above,
                                        ; which clobbers r8)
            mov     rb, zp_start
            ghi     r8
            str     rb
            inc     rb
            glo     r8
            str     rb                  ; zp_start = pos
            mov     rf, zp_length
            ldi     1
            str     rf                  ; zp_length = 1

            mov     r9, r8
            add16   r9, 1
            mov     rb, zp_pos
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb                  ; zp_pos = pos + 1
            lbr     zpt_lookup

zpt_skip_space:
            mov     r9, r8
            add16   r9, 1
            mov     rb, zp_pos
            ghi     r9
            str     rb
            inc     rb
            glo     r9
            str     rb                  ; zp_pos = pos + 1
            lbr     zpt_loop

zpt_lookup:
            mov     rf, zp_length
            ldn     rf
            plo     rc                  ; rc.0 = length
            smi     6
            lbnf    zpt_rl_ok           ; length < 6: keep as-is
            ldi     6
            plo     rc                  ; length >= 6: cap to 6
zpt_rl_ok:
            mov     rf, zp_read_len
            glo     rc
            str     rf                  ; zp_read_len = read_len

            mov     rf, zp_start
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = start
            mov     rf, zp_text_addr
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = text_addr
            add16   r8, r9              ; r8 = text_addr + start

            mov     rf, zp_word_buf
zpt_copy:
            glo     rc
            lbz     zpt_copy_done
            ldn     r8
            str     rf
            inc     r8
            inc     rf
            dec     rc
            lbr     zpt_copy
zpt_copy_done:

            mov     rd, zp_word_buf
            mov     rf, zp_read_len
            ldn     rf
            call    zdict_find_word     ; rf = entry addr (0 if not
                                        ; found), DF=1 if unencodable
            lbdf    zpt_error

            mov     r8, rf              ; r8 = entry_addr -- survives
                                        ; the rest of this record write
                                        ; (nothing below calls anything)
            mov     rf, zp_parse_cursor
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = parse cursor address

            ghi     r8
            str     r9
            inc     r9
            glo     r8
            str     r9
            inc     r9

            mov     rf, zp_length
            ldn     rf
            str     r9
            inc     r9

            mov     rf, zp_start+1
            ldn     rf
            plo     rc                  ; rc.0 = start (low byte --
                                        ; start always fits a byte)
            mov     rf, zp_text_offset
            ldn     rf
            str     r2
            glo     rc
            add                         ; d = start + text_offset
            str     r9
            inc     r9

            mov     rf, zp_parse_cursor
            ghi     r9
            str     rf
            inc     rf
            glo     r9
            str     rf                  ; zp_parse_cursor = r9

            mov     rf, zp_word_count
            ldn     rf
            adi     1
            str     rf                  ; zp_word_count += 1
            lbr     zpt_loop

zpt_done:
            mov     rf, zp_parse_addr
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = parse_addr (the value)
            add16   r8, 1
            mov     rb, zp_word_count
            ldn     rb
            str     r8
            clc
            rtn

zpt_error:
            stc
            rtn
            endp

            proc    _zparse_data
zp_text_addr:       dw      0
zp_text_length:      db      0
zp_text_offset:      db      0
zp_parse_addr:       dw      0
zp_pos:              dw      0
zp_word_count:       db      0
zp_parse_cursor:     dw      0
zp_start:            dw      0
zp_length:           db      0
zp_read_len:         db      0
zp_word_buf:         ds      6
                public  zp_text_addr
                public  zp_text_length
                public  zp_text_offset
                public  zp_parse_addr
                public  zp_pos
                public  zp_word_count
                public  zp_parse_cursor
                public  zp_start
                public  zp_length
                public  zp_read_len
                public  zp_word_buf
            endp
