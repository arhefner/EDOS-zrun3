;
; zdec.asm - V3 Z-text decoder
;
; Mirrors host/ztext.c's ztext_decode exactly, including its one
; remaining known simplification: z-char 6 in A2 introduces a 10-bit
; ZSCII escape in the real Z-machine standard, which neither this nor
; the host decoder implements -- both hold a placeholder space in that
; slot (index 0) instead.
;
; BUG FIX: zdec_a2 used to have NO newline entry for z-char 7, so the
; whole table -- every digit and every punctuation mark -- was shifted
; one z-char too early, and it ran one entry short of z-char 31. Real
; story text came out with ':' as '(', ',' as '!', '.' as ',', and
; every embedded newline as '0' ("...Underground Empire0Copyright..."
; in ZORK I's own banner). host/ztext.c carried the identical off-by-
; one, which is exactly why the host reference tests never caught it;
; both are fixed together, along with lib/zdict.asm's own encoder,
; whose A2 punctuation codes were off by the same one.
;
; Z-char 1-3 (abbreviations) ARE supported: the marker's index is
; 32*(zchar-1) + the immediately following z-char, looked up as a
; guest-address word at zdec_abbrev_table + 2*index (set once via
; zdec_init), itself a packed address (*2 for the real byte address) of
; the abbreviation's own text, fetched through zmread_bytes (guest-
; address, cache-aware) and decoded inline into the SAME output stream
; at the current position. Per the Z-machine standard, an abbreviation
; string may not itself reference a further abbreviation -- z-char 1-3
; found while decoding an abbreviation's own text is a decode error
; (DF=1), not a second expansion.
;
; Because expanding an abbreviation needs to look ahead across a word
; boundary (the index byte can be the first z-char of the NEXT word,
; if the marker was the last z-char of the current one) and can call
; out to zmread/zmread_bytes partway through, the old "walk three fixed
; positions per word, everything survives in registers" shape from
; before abbreviation support doesn't fit any more: nothing can be
; trusted to survive an arbitrary call (same lesson as lib/zmem.asm's
; own zmread_cache_go fix). Z-char iteration is now a pull-based
; stream (zdec_next_o/zdec_next_a: "give me the next z-char, refilling
; from a new word as needed") with its own state kept entirely in
; memory, one instance for the outer text being decoded and a second,
; completely separate instance for (at most one level of) an
; abbreviation's own text -- duplicated rather than parameterized by a
; runtime base pointer, matching this project's own established style
; of fixed, named data symbols rather than runtime struct-base
; arithmetic, and sidestepping any "which context is live right now"
; register-survival question entirely. The two instances share only
; the OUTPUT cursor (zdec_out, a single continuous stream); each has
; its own alphabet_set, matching the Z-machine standard (an
; abbreviation's own shift state starts fresh and never leaks either
; direction across the boundary).
;
; Register budget matches the rest of this project: only R7-RD and
; RF, no R1, no RE. No routine here keeps anything live across a call
; except by way of the named memory fields above.
;

#include    include/opcodes.def

            extrn   zdec_a0
            extrn   zdec_a1
            extrn   zdec_a2

            extrn   zdec_out
            extrn   zdec_abbrev_table
            extrn   zdec_o_cursor
            extrn   zdec_o_length
            extrn   zdec_o_word
            extrn   zdec_o_pos
            extrn   zdec_o_end
            extrn   zdec_o_done
            extrn   zdec_o_alphabet
            extrn   zdec_o_escape
            extrn   zdec_a_cursor
            extrn   zdec_a_length
            extrn   zdec_a_word
            extrn   zdec_a_pos
            extrn   zdec_a_end
            extrn   zdec_a_done
            extrn   zdec_a_alphabet
            extrn   zdec_a_escape
            extrn   zdec_abbrev_buf

            extrn   zdec_next_o
            extrn   zdec_next_a
            extrn   zdec_emit_o
            extrn   zdec_emit_a
            extrn   zdec_run_outer
            extrn   zdec_run_abbrev

            extrn   zmread16
            extrn   zmread_bytes

; zdec_decode: RD = packed z-text address (a real host pointer, not a
; guest address -- the caller is responsible for getting these bytes
; resident first, e.g. via zmread_bytes itself), RF = output buffer
; address, RC = length in bytes (must be even). Writes decoded,
; NUL-terminated ASCII to the output buffer, expanding any
; abbreviation references along the way. DF=1 for an odd length, an
; unsupported/malformed abbreviation reference, or a zmread/
; zmread_bytes failure while fetching one.
            proc    zdec_decode
            glo     rc
            ani     1
            lbnz    zdd_error           ; odd length: reject

            mov     r7, zdec_out
            ghi     rf
            str     r7
            inc     r7
            glo     rf
            str     r7                  ; zdec_out = rf

            mov     r7, zdec_o_cursor
            ghi     rd
            str     r7
            inc     r7
            glo     rd
            str     r7                  ; zdec_o_cursor = rd
            mov     r7, zdec_o_length
            ghi     rc
            str     r7
            inc     r7
            glo     rc
            str     r7                  ; zdec_o_length = rc
            mov     r7, zdec_o_pos
            ldi     3
            str     r7                  ; need a new word on first pull
            mov     r7, zdec_o_end
            ldi     0
            str     r7
            mov     r7, zdec_o_done
            ldi     0
            str     r7
            mov     r7, zdec_o_alphabet
            ldi     0
            str     r7

            call    zdec_run_outer
            lbdf    zdd_error

            mov     r7, zdec_out
            lda     r7
            phi     r8
            ldn     r7
            plo     r8                  ; r8 = *zdec_out (final position)
            ldi     0
            str     r8                  ; NUL-terminate
            clc
            rtn

zdd_error:
            stc
            rtn
            endp

; zdec_init: RD = abbreviation table guest address. Must be called
; once before any zdec_decode call that might encounter an
; abbreviation reference (z-char 1-3); until a real story loader
; exists, callers (diags) set this directly.
            proc    zdec_init
            mov     r7, zdec_abbrev_table
            ghi     rd
            str     r7
            inc     r7
            glo     rd
            str     r7
            clc
            rtn
            endp

; zdec_run_outer (internal): drives the OUTER context (zdec_o_*,
; already initialized by zdec_decode), writing decoded ASCII through
; zdec_out (also already initialized), until the stream is exhausted.
; Abbreviations (z-char 1-3) ARE expanded here. Returns DF=1 on any
; failure (malformed abbreviation reference, a zmread/zmread_bytes
; failure, or the nested abbreviation's own decode failure).
            proc    zdec_run_outer
zro_loop:
            call    zdec_next_o
            lbdf    zro_success         ; exhausted: clean end

; A ZSCII escape's two following z-chars are RAW 5-bit halves, not
; text: values 1-3 there are NOT abbreviation markers and 0 is not a
; space, so the escape state (see zdec_emit_o) is checked before any
; of that interpretation happens.
            plo     ra
            mov     r7, zdec_o_alphabet
            ldn     r7
            smi     3                   ; DF=1 (no borrow) means state
                                        ; >= 3, i.e. mid-escape
            lbdf    zro_emit

            glo     ra
            plo     ra                  ; ra.0 = zchar -- NOT r8: the
                                        ; abbreviation branch below
                                        ; makes a second call to
                                        ; zdec_next_o to peek the index
                                        ; byte, and that call clobbers
                                        ; r7/r8/r9/rb internally (see
                                        ; its own header), so zchar
                                        ; can't survive in any of those
                                        ; -- ra is untouched by it

            glo     ra
            lbz     zro_emit            ; zchar == 0: space, not an
                                        ; abbreviation marker

            glo     ra
            smi     4                   ; DF=1 (no borrow) means
                                        ; zchar >= 4 -- covers the two
                                        ; shifts and every real letter,
                                        ; none of which are
                                        ; abbreviation markers
            lbdf    zro_emit

; zchar is 1, 2, or 3: an abbreviation marker. Peek the following
; z-char for the index -- reuses zdec_next_o itself. An index of 5 in
; the final word's last slot reads back correctly now that the bogus
; padding rule is gone (see this file's own note below); before, it
; was discarded and this peek reported the stream exhausted, i.e. a
; malformed reference.
            call    zdec_next_o
            lbdf    zro_fail            ; marker with nothing following:
                                        ; malformed
            plo     r9                  ; r9.0 = the index byte

            glo     ra                  ; d = zchar (1, 2, or 3),
                                        ; still intact -- the call
                                        ; above never touched ra
            smi     1                   ; d = zchar-1 (0, 1, or 2)
            shl
            shl
            shl
            shl
            shl                         ; d = (zchar-1)*32 (0, 32, or
                                        ; 64 -- fits a byte, no carry
                                        ; possible for these inputs)
            str     r2
            glo     r9                  ; d = the index byte (0-31)
            add                         ; d = (zchar-1)*32 + index byte
                                        ; = the abbreviation index
                                        ; (0-95)
            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:index

            mov     r7, zdec_abbrev_table
            lda     r7
            phi     r8
            ldn     r7
            plo     r8                  ; r8 = zdec_abbrev_table
            shl16   ra                  ; ra = index*2
            add16   r8, ra              ; r8 = entry_addr (guest addr)

            mov     rd, r8
            call    zmread16            ; rf = the table entry (a
                                        ; packed address), df=err
            lbdf    zro_fail

            mov     r9, rf              ; r9 = the table entry (a
                                        ; packed address)
            glo     r9
            shl
            plo     r9
            ghi     r9
            shlc
            phi     r9                  ; r9 = entry*2, wrapped to 16
                                        ; bits; DF = the 17th bit --
                                        ; doubling a packed address can
                                        ; legitimately carry into it
                                        ; for a story file over 64K,
                                        ; which a plain shl16 would
                                        ; silently discard (see
                                        ; zds_print_paddr's own fix,
                                        ; same reasoning)
            ldi     0
            plo     ra
            lbnf    zro_abbrev_no_carry
            ldi     1
            plo     ra
zro_abbrev_no_carry:
            ldi     0
            phi     ra                  ; ra = target address's high
                                        ; word

            mov     rd, r9
            mov     rf, zdec_abbrev_buf
            mov     rc, 64
            call    zmread_bytes        ; rc = actual bytes copied
                                        ; (<=64); df=1 only if even the
                                        ; very first byte failed
            lbdf    zro_fail

            glo     rc
            ani     $fe
            plo     rc                  ; round down to even -- same
                                        ; generous-bound convention as
                                        ; print_addr/print_paddr's own
                                        ; unmeasured text

            mov     r7, zdec_a_cursor
            mov     r8, zdec_abbrev_buf
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7                  ; zdec_a_cursor = zdec_abbrev_buf
            mov     r7, zdec_a_length
            ghi     rc
            str     r7
            inc     r7
            glo     rc
            str     r7                  ; zdec_a_length = actual count
            mov     r7, zdec_a_pos
            ldi     3
            str     r7
            mov     r7, zdec_a_end
            ldi     0
            str     r7
            mov     r7, zdec_a_done
            ldi     0
            str     r7
            mov     r7, zdec_a_alphabet
            ldi     0
            str     r7                  ; fresh alphabet_set -- an
                                        ; abbreviation's own shift
                                        ; state never leaks either
                                        ; direction across the boundary

            call    zdec_run_abbrev
            lbdf    zro_fail

            lbr     zro_loop            ; resume the outer stream

zro_emit:
            glo     ra
            plo     rf
            call    zdec_emit_o
            lbr     zro_loop

zro_success:
            clc
            rtn
zro_fail:
            stc
            rtn
            endp

; zdec_run_abbrev (internal): drives the ABBREVIATION context
; (zdec_a_*, already initialized by zdec_run_outer), writing decoded
; ASCII through the SAME shared zdec_out, until the stream is
; exhausted. Z-char 1-3 here is a nested abbreviation reference, which
; the Z-machine standard forbids -- DF=1, not a second expansion.
            proc    zdec_run_abbrev
zra_loop:
            call    zdec_next_a
            lbdf    zra_success

            plo     r8                  ; r8.0 = zchar

            mov     r7, zdec_a_alphabet ; mid-escape? then this z-char
            ldn     r7                  ; is a raw half -- see the same
            smi     3                   ; guard in zdec_run_outer
            lbdf    zra_emit

            glo     r8
            lbz     zra_emit            ; zchar == 0

            glo     r8
            smi     4
            lbdf    zra_emit            ; zchar >= 4

            stc                         ; zchar 1-3: nested abbreviation
                                        ; reference -- invalid
            rtn

zra_emit:
            glo     r8
            plo     rf
            call    zdec_emit_a
            lbr     zra_loop

zra_success:
            clc
            rtn
            endp

; BUG FIX: both streams below used to treat "z-char 5 in the third
; slot of the final word" as padding and end the string there. That
; rule is this decoder's own invention -- the Z-machine standard has no
; such marker: a string simply ends once every z-char of the word with
; bit 15 set has been consumed, and the 5s a shorter string is padded
; with are ordinary shift-to-A2 z-chars that happen to produce no
; output. The heuristic gets the same answer for real padding, but
; silently eats a legitimate final z-char of 5 -- most visibly the
; INDEX of a trailing abbreviation reference. ZORK I's Kitchen
; description ends with abbreviation 5 ("is "), so decoding it saw the
; marker z-char 1 with nothing following and reported a malformed
; abbreviation. host/ztext.c's zchar_stream_next carried the identical
; rule, which is why the host tests agreed with the port.

; zdec_next_o (internal): no arguments (drives the OUTER context).
; Returns D = the next z-char (0-31), DF=1 if the outer stream has no
; more (a clean end, not an error) -- i.e. once all three z-chars of
; the word with bit 15 set have been handed out. Makes no calls --
; R7-RB freely usable as scratch.
            proc    zdec_next_o
            mov     r7, zdec_o_pos
            ldn     r7
            xri     3
            lbnz    zno_have_word       ; pos != 3: word already loaded

            mov     r7, zdec_o_done
            ldn     r7
            lbnz    zno_exhausted

            mov     r7, zdec_o_length
            lda     r7
            phi     r9
            ldn     r7
            plo     r9                  ; r9 = remaining length
            glo     r9
            lbnz    zno_have_length
            ghi     r9
            lbnz    zno_have_length
            mov     r7, zdec_o_done
            ldi     1
            str     r7
            lbr     zno_exhausted

zno_have_length:
            mov     r7, zdec_o_cursor
            lda     r7
            phi     r8
            ldn     r7
            plo     r8                  ; r8 = cursor (host pointer)
            lda     r8                  ; d = word high byte; r8++
            phi     rb
            ldn     r8                  ; d = word low byte
            plo     rb                  ; rb = word
            inc     r8                  ; r8 = cursor+2

            mov     r7, zdec_o_cursor
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7                  ; zdec_o_cursor = cursor+2

            sub16   r9, 2               ; r9 = remaining-2
            mov     r7, zdec_o_length
            ghi     r9
            str     r7
            inc     r7
            glo     r9
            str     r7                  ; zdec_o_length -= 2

            mov     r7, zdec_o_word
            ghi     rb
            str     r7
            inc     r7
            glo     rb
            str     r7                  ; zdec_o_word = word

            ghi     rb
            ani     $80
            lbz     zno_not_end
            mov     r7, zdec_o_end
            ldi     1
            str     r7
            lbr     zno_pos_reset
zno_not_end:
            mov     r7, zdec_o_end
            ldi     0
            str     r7
zno_pos_reset:
            mov     r7, zdec_o_pos
            ldi     0
            str     r7

zno_have_word:
            mov     r7, zdec_o_word
            lda     r7
            phi     rb
            ldn     r7
            plo     rb                  ; rb = word

            mov     r7, zdec_o_pos
            ldn     r7
            lbz     zno_pos0
            smi     1
            lbz     zno_pos1

            glo     rb                  ; pos == 2: bits 0-4
            ani     $1f
            lbr     zno_have_zchar
zno_pos1:
            mov     r8, rb
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8                  ; r8 = word >> 5
            glo     r8
            ani     $1f
            lbr     zno_have_zchar
zno_pos0:
            mov     r8, rb
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8                  ; r8 = word >> 10
            glo     r8
            ani     $1f

zno_have_zchar:
            plo     r9                  ; r9.0 = zchar

zno_not_padding:
            mov     r7, zdec_o_pos
            ldn     r7
            adi     1
            str     r7
            xri     3
            lbnz    zno_return
            mov     r7, zdec_o_end
            ldn     r7
            lbz     zno_return
            mov     r7, zdec_o_done
            ldi     1
            str     r7

zno_return:
            glo     r9
            clc
            rtn

zno_exhausted:
            stc
            rtn
            endp

; zdec_next_a (internal): identical to zdec_next_o above, driving the
; ABBREVIATION context instead. Kept as a separate copy rather than
; parameterized by a runtime context-base pointer, matching this
; project's own established style of fixed, named data symbols instead
; of runtime struct-base arithmetic -- see this file's own header
; comment for why.
            proc    zdec_next_a
            mov     r7, zdec_a_pos
            ldn     r7
            xri     3
            lbnz    zna_have_word

            mov     r7, zdec_a_done
            ldn     r7
            lbnz    zna_exhausted

            mov     r7, zdec_a_length
            lda     r7
            phi     r9
            ldn     r7
            plo     r9
            glo     r9
            lbnz    zna_have_length
            ghi     r9
            lbnz    zna_have_length
            mov     r7, zdec_a_done
            ldi     1
            str     r7
            lbr     zna_exhausted

zna_have_length:
            mov     r7, zdec_a_cursor
            lda     r7
            phi     r8
            ldn     r7
            plo     r8
            lda     r8
            phi     rb
            ldn     r8
            plo     rb
            inc     r8

            mov     r7, zdec_a_cursor
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7

            sub16   r9, 2
            mov     r7, zdec_a_length
            ghi     r9
            str     r7
            inc     r7
            glo     r9
            str     r7

            mov     r7, zdec_a_word
            ghi     rb
            str     r7
            inc     r7
            glo     rb
            str     r7

            ghi     rb
            ani     $80
            lbz     zna_not_end
            mov     r7, zdec_a_end
            ldi     1
            str     r7
            lbr     zna_pos_reset
zna_not_end:
            mov     r7, zdec_a_end
            ldi     0
            str     r7
zna_pos_reset:
            mov     r7, zdec_a_pos
            ldi     0
            str     r7

zna_have_word:
            mov     r7, zdec_a_word
            lda     r7
            phi     rb
            ldn     r7
            plo     rb

            mov     r7, zdec_a_pos
            ldn     r7
            lbz     zna_pos0
            smi     1
            lbz     zna_pos1

            glo     rb
            ani     $1f
            lbr     zna_have_zchar
zna_pos1:
            mov     r8, rb
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            glo     r8
            ani     $1f
            lbr     zna_have_zchar
zna_pos0:
            mov     r8, rb
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            shr16   r8
            glo     r8
            ani     $1f

zna_have_zchar:
            plo     r9

zna_not_padding:
            mov     r7, zdec_a_pos
            ldn     r7
            adi     1
            str     r7
            xri     3
            lbnz    zna_return
            mov     r7, zdec_a_end
            ldn     r7
            lbz     zna_return
            mov     r7, zdec_a_done
            ldi     1
            str     r7

zna_return:
            glo     r9
            clc
            rtn

zna_exhausted:
            stc
            rtn
            endp

; zdec_emit_o (internal): RF.0 = z-char (0, 4, 5, or >=6 -- the caller
; already handled 1-3 separately). Emits the corresponding character
; (or none, for a shift z-char) to *zdec_out, advancing it, and
; updates zdec_o_alphabet. Makes no calls.
            proc    zdec_emit_o
; ---- a ZSCII escape in progress (alphabet state 3 or 4) consumes this
; z-char as a raw 5-bit half, ahead of every other interpretation ----
            mov     r7, zdec_o_alphabet
            ldn     r7
            smi     3
            lbnf    zeo_not_escape      ; DF=0 (borrow): state < 3
            lbz     zeo_esc_high        ; state == 3: first half

            mov     r7, zdec_o_escape   ; state == 4: second half
            ldn     r7
            shl
            shl
            shl
            shl
            shl                         ; d = high half << 5
            str     r2
            glo     rf
            or                          ; d = the ZSCII character
            plo     rb                  ; stash it: the destination
                                        ; reload below clobbers d
            mov     r7, zdec_out
            lda     r7
            phi     r8
            ldn     r7
            plo     r8
            glo     rb
            str     r8
            inc     r8
            mov     r7, zdec_out
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7
            mov     r7, zdec_o_alphabet
            ldi     0
            str     r7                  ; escape complete, back to A0
            clc
            rtn

zeo_esc_high:
            mov     r7, zdec_o_escape
            glo     rf
            str     r7                  ; stash the high 5 bits
            mov     r7, zdec_o_alphabet
            ldi     4
            str     r7                  ; expect the low half next
            clc
            rtn

zeo_not_escape:
            glo     rf
            lbnz    zeo_nonzero
            mov     r7, zdec_out
            lda     r7
            phi     r8
            ldn     r7
            plo     r8                  ; r8 = *zdec_out
            ldi     ' '
            str     r8
            inc     r8
            mov     r7, zdec_out
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7
            clc
            rtn

zeo_nonzero:
            glo     rf
            xri     4
            lbz     zeo_shift1
            glo     rf
            xri     5
            lbz     zeo_shift2

; real letter (zchar >= 6)
            glo     rf
            smi     6
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:(zchar-6)

            mov     r7, zdec_o_alphabet
            ldn     r7
            lbz     zeo_use_a0
            mov     r7, zdec_o_alphabet
            ldn     r7
            smi     1
            lbz     zeo_use_a1
            glo     r9
            lbnz    zeo_a2_table        ; index != 0, an ordinary A2
                                        ; character
            ghi     r9
            lbnz    zeo_a2_table
            mov     r7, zdec_o_alphabet ; A2 z-char 6: begin a 10-bit
            ldi     3                   ; ZSCII escape -- the next two
            str     r7                  ; z-chars are its halves
            clc
            rtn
zeo_a2_table:
            mov     r8, zdec_a2
            lbr     zeo_have_table
zeo_use_a1:
            mov     r8, zdec_a1
            lbr     zeo_have_table
zeo_use_a0:
            mov     r8, zdec_a0
zeo_have_table:
            add16   r8, r9
            ldn     r8                  ; d = the letter
            plo     rb                  ; rb.0 = the letter, stashed --
                                        ; the destination-pointer
                                        ; reload below uses lda/ldn,
                                        ; which would otherwise clobber
                                        ; d before it's written out

            mov     r7, zdec_out
            lda     r7
            phi     r9
            ldn     r7
            plo     r9                  ; r9 = *zdec_out
            glo     rb                  ; d = the letter, reloaded
            str     r9
            inc     r9
            mov     r7, zdec_out
            ghi     r9
            str     r7
            inc     r7
            glo     r9
            str     r7

            mov     r7, zdec_o_alphabet
            ldi     0
            str     r7                  ; a real letter always clears
                                        ; any pending shift
            clc
            rtn

zeo_shift1:
            mov     r7, zdec_o_alphabet
            ldi     1
            str     r7
            clc
            rtn

zeo_shift2:
            mov     r7, zdec_o_alphabet
            ldi     2
            str     r7
            clc
            rtn
            endp

; zdec_emit_a (internal): identical to zdec_emit_o above, driving the
; ABBREVIATION context's own alphabet_set instead -- but still writing
; through the SAME shared zdec_out (the output stream is one
; continuous sequence regardless of which context is currently
; producing it).
            proc    zdec_emit_a
            mov     r7, zdec_a_alphabet ; mid-escape? see zdec_emit_o's
            ldn     r7                  ; own copy of this for the full
            smi     3                   ; explanation
            lbnf    zea_not_escape
            lbz     zea_esc_high

            mov     r7, zdec_a_escape
            ldn     r7
            shl
            shl
            shl
            shl
            shl
            str     r2
            glo     rf
            or
            plo     rb
            mov     r7, zdec_out
            lda     r7
            phi     r8
            ldn     r7
            plo     r8
            glo     rb
            str     r8
            inc     r8
            mov     r7, zdec_out
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7
            mov     r7, zdec_a_alphabet
            ldi     0
            str     r7
            clc
            rtn

zea_esc_high:
            mov     r7, zdec_a_escape
            glo     rf
            str     r7
            mov     r7, zdec_a_alphabet
            ldi     4
            str     r7
            clc
            rtn

zea_not_escape:
            glo     rf
            lbnz    zea_nonzero
            mov     r7, zdec_out
            lda     r7
            phi     r8
            ldn     r7
            plo     r8
            ldi     ' '
            str     r8
            inc     r8
            mov     r7, zdec_out
            ghi     r8
            str     r7
            inc     r7
            glo     r8
            str     r7
            clc
            rtn

zea_nonzero:
            glo     rf
            xri     4
            lbz     zea_shift1
            glo     rf
            xri     5
            lbz     zea_shift2

            glo     rf
            smi     6
            plo     r9
            ldi     0
            phi     r9

            mov     r7, zdec_a_alphabet
            ldn     r7
            lbz     zea_use_a0
            mov     r7, zdec_a_alphabet
            ldn     r7
            smi     1
            lbz     zea_use_a1
            glo     r9
            lbnz    zea_a2_table
            ghi     r9
            lbnz    zea_a2_table
            mov     r7, zdec_a_alphabet ; A2 z-char 6: begin a 10-bit
            ldi     3                   ; ZSCII escape
            str     r7
            clc
            rtn
zea_a2_table:
            mov     r8, zdec_a2
            lbr     zea_have_table
zea_use_a1:
            mov     r8, zdec_a1
            lbr     zea_have_table
zea_use_a0:
            mov     r8, zdec_a0
zea_have_table:
            add16   r8, r9
            ldn     r8
            plo     rb

            mov     r7, zdec_out
            lda     r7
            phi     r9
            ldn     r7
            plo     r9
            glo     rb
            str     r9
            inc     r9
            mov     r7, zdec_out
            ghi     r9
            str     r7
            inc     r7
            glo     r9
            str     r7

            mov     r7, zdec_a_alphabet
            ldi     0
            str     r7
            clc
            rtn

zea_shift1:
            mov     r7, zdec_a_alphabet
            ldi     1
            str     r7
            clc
            rtn

zea_shift2:
            mov     r7, zdec_a_alphabet
            ldi     2
            str     r7
            clc
            rtn
            endp

            proc    _zdec_data
zdec_a0:    db      "abcdefghijklmnopqrstuvwxyz"
zdec_a1:    db      "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
zdec_a2:    db      " ",10,"0123456789.,!?_#'",34,"/",92,"-:()"
                                    ; index 0 = z-char 6 (the
                                    ; 10-bit ZSCII escape slot,
                                    ; unimplemented -- see this
                                    ; file's own header); index 1 =
                                    ; z-char 7, a NEWLINE per the
                                    ; Z-machine standard, emitted as
                                    ; 10 to match zdispatch.asm's own
                                    ; zdisp_newline_buf. Indices
                                    ; 2..25 are z-chars 8..31, ending
                                    ; at ')' exactly as the standard
                                    ; specifies.
zdec_out:              dw      0
zdec_abbrev_table:     dw      0
zdec_o_cursor:         dw      0
zdec_o_length:         dw      0
zdec_o_word:           dw      0
zdec_o_pos:            db      0
zdec_o_end:            db      0
zdec_o_done:           db      0
zdec_o_alphabet:       db      0
zdec_o_escape:         db      0   ; the high 5 bits of a ZSCII escape
                                   ; in progress (alphabet state 4)
zdec_a_cursor:         dw      0
zdec_a_length:         dw      0
zdec_a_word:           dw      0
zdec_a_pos:            db      0
zdec_a_end:            db      0
zdec_a_done:           db      0
zdec_a_alphabet:       db      0
zdec_a_escape:         db      0   ; as zdec_o_escape, for the
                                   ; abbreviation context
zdec_abbrev_buf:       ds      64      ; one abbreviation's own packed
                                       ; text, fetched via zmread_bytes
                                       ; -- generous for any real
                                       ; Infocom abbreviation (always
                                       ; short)
                public  zdec_a0
                public  zdec_a1
                public  zdec_a2
                public  zdec_out
                public  zdec_abbrev_table
                public  zdec_o_cursor
                public  zdec_o_length
                public  zdec_o_word
                public  zdec_o_pos
                public  zdec_o_end
                public  zdec_o_done
                public  zdec_o_alphabet
                public  zdec_o_escape
                public  zdec_a_cursor
                public  zdec_a_length
                public  zdec_a_word
                public  zdec_a_pos
                public  zdec_a_end
                public  zdec_a_done
                public  zdec_a_alphabet
                public  zdec_a_escape
                public  zdec_abbrev_buf
            endp
