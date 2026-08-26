;
; zdec.asm - V3 Z-text decoder
;
; Mirrors host/ztext.c's ztext_decode exactly, including its two
; known simplifications: z-chars 1-3 (abbreviations) are unsupported
; (DF=1, matching the host's `return -1`), and the A2 table has no
; entry for z-char 31 (the real Z-machine standard uses that slot to
; introduce a 10-bit ZSCII escape, which neither this nor the host
; decoder implements) -- both decoders read one byte past zdec_a2 in
; that case, deterministically but not meaningfully, exactly mirroring
; the host's own undefined-but-deterministic static-array read. Fixing
; that is future scope, not a regression introduced here.
;
; shift_once (host: sticky until the next real letter or a fresh
; shift) is folded into alphabet_set here: `alphabet_set != 0` is
; provably equivalent to the host's `shift_once` at every point in the
; host's own control flow, so there is no separate flag to track.
;
; No calls happen inside zdec_decode's own word/bounds bookkeeping, so
; R8 (packed-text cursor), R9 (remaining length), RA (output cursor),
; RB (the current word), and RC (its end-of-string bit) all survive
; freely -- except across the one call to zdec_emit_zchar, which is
; deliberately written to avoid every one of those registers (it uses
; only RF/RD/R7/RA) precisely so the caller's word-processing state
; needs no special handling around that call.
;
; Register budget matches the rest of this project: only R7-RD and
; RF, no R1, no RE.
;

#include    include/opcodes.def

            extrn   zdec_a0
            extrn   zdec_a1
            extrn   zdec_a2

            extrn   zdec_emit_zchar

; zdec_decode: RD = packed z-text address, RF = output buffer address,
; RC = length in bytes (must be even). Writes decoded, NUL-terminated
; ASCII to the output buffer. DF=1 for an odd length, an unsupported
; z-char (1-3), or (see the header comment) a not-fully-specified A2
; z-char 31.
            proc    zdec_decode
            mov     r8, rd              ; r8 = packed-text cursor
            mov     ra, rf              ; ra = output cursor
            mov     r9, rc              ; r9 = remaining length (bytes)
            ldi     0
            plo     r7                  ; r7.0 = alphabet_set

            glo     r9
            ani     1
            lbnz    zdec_error          ; odd length: reject

zdec_word_loop:
            glo     r9
            lbnz    zdec_have_word
            ghi     r9
            lbnz    zdec_have_word
            lbr     zdec_success        ; remaining == 0: done

zdec_have_word:
            lda     r8                  ; d = word's high byte, r8++
            phi     rb
            ldn     r8                  ; d = word's low byte (r8 not
                                        ; advanced by ldn)
            plo     rb                  ; rb = word
            inc     r8                  ; r8 now past both bytes

            ghi     rb
            ani     $80
            plo     rc                  ; rc.0 = end-of-string flag

            sub16   r9, 2               ; remaining -= 2

; ---- z-char 0: bits 10-14 ----
            mov     rd, rb
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd                  ; rd = word >> 10
            glo     rd
            ani     $1f
            plo     rf
            call    zdec_emit_zchar
            lbdf    zdec_error

; ---- z-char 1: bits 5-9 ----
            mov     rd, rb
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd
            shr16   rd                  ; rd = word >> 5
            glo     rd
            ani     $1f
            plo     rf
            call    zdec_emit_zchar
            lbdf    zdec_error

; ---- z-char 2: bits 0-4 (the one that can signal end-of-string
; padding instead of a real character) ----
            glo     rb
            ani     $1f
            plo     rf                  ; rf.0 = z-char 2
            glo     rc
            lbz     zdec_zchar2_emit    ; not the last word: always a
                                        ; real z-char
            glo     rf
            xri     5
            lbz     zdec_word_done      ; end-of-string AND z-char==5:
                                        ; padding, not a real character

zdec_zchar2_emit:
            call    zdec_emit_zchar
            lbdf    zdec_error

            glo     rc
            lbnz    zdec_word_done      ; end-of-string: stop after
                                        ; this word
            lbr     zdec_word_loop

zdec_word_done:
zdec_success:
            mov     rf, ra
            ldi     0
            str     rf                  ; NUL-terminate the output
            clc
            rtn

zdec_error:
            stc
            rtn
            endp

; zdec_emit_zchar (internal): RF.0 = z-char (set immediately before
; the call). Emits the corresponding character (or none, for a shift
; z-char) to the output buffer at RA, advancing RA, and updates R7
; (alphabet_set). DF=1 for an unsupported z-char (1-3).
;
; Deliberately avoids R8/R9/RB/RC so zdec_decode's own word-processing
; state needs no special handling around this call.
            proc    zdec_emit_zchar
            glo     rf
            lbnz    zez_nonzero
            ldi     ' '
            str     ra
            inc     ra
            clc
            rtn

zez_nonzero:
            glo     rf
            smi     6
            lbnf    zez_shift_or_error  ; z-char 1-5

            glo     rf
            smi     6
            plo     rd
            ldi     0
            phi     rd                  ; rd = 0:(z-char - 6)

            glo     r7
            lbz     zez_use_a0
            glo     r7
            smi     1
            lbz     zez_use_a1
            mov     rf, zdec_a2
            lbr     zez_have_table
zez_use_a1:
            mov     rf, zdec_a1
            lbr     zez_have_table
zez_use_a0:
            mov     rf, zdec_a0
zez_have_table:
            add16   rf, rd
            ldn     rf
            str     ra
            inc     ra
            ldi     0
            plo     r7                  ; a real letter always clears
                                        ; any pending shift
            clc
            rtn

zez_shift_or_error:
            glo     rf
            xri     4
            lbz     zez_shift1
            glo     rf
            xri     5
            lbz     zez_shift2
            stc
            rtn                         ; z-char 1-3: unsupported
                                        ; (abbreviations)

zez_shift1:
            ldi     1
            plo     r7
            clc
            rtn

zez_shift2:
            ldi     2
            plo     r7
            clc
            rtn
            endp

            proc    _zdec_data
zdec_a0:    db      "abcdefghijklmnopqrstuvwxyz"
zdec_a1:    db      "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
zdec_a2:    db      " 0123456789.,!?_#'",34,"/",92,"-:()"
                public  zdec_a0
                public  zdec_a1
                public  zdec_a2
            endp
