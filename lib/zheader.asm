;
; zheader.asm - V3 story header parsing (the 1802 port of
; host/story_header.c's story_header_parse, minus its declared-vs-
; actual file length cross-check: a V3 file can legitimately exceed
; 65535 bytes -- Zork I alone is 84876 -- which doesn't fit this
; project's 16-bit guest-address type, and nothing the loader actually
; does needs the total length as a single number (zminit only needs
; dynamic_end; zcread's own EOF handling, fixed in the zcache EOF
; incident, already reports a real end-of-file cleanly on its own
; without the loader needing to predict it up front). Checksum
; verification is likewise not implemented -- most real interpreters
; treat it as informational, not a hard gate, and it would require an
; extra full pass over the file this early in loading. Also drops
; host's own "dictionary >= static_memory is invalid" check: that's
; backwards -- the dictionary is read-only and, in every real compiled
; V3 file (ZORK I's own real header included: dictionary=0x3b21,
; static_memory=0x2e53), normally lives IN static memory, not below
; it. That check would reject virtually every real game; found by
; validating this parser against ZORK I's actual header instead of
; only synthetic test data, and fixed in host/story_header.c too (the
; two were meant to mirror each other and had both carried the same
; bug since before this session).
;
; zheader_parse: RD = host pointer to the story file's first 64+ bytes
; (already read into memory by the caller -- this runs before any
; guest-address machinery exists, so it works on a real pointer, not a
; guest address). Validates the header and stores its fields into this
; module's own globals. DF=1 if the version isn't 3, or if any table
; address falls outside the ordering the Z-machine standard requires.
;
; No calls happen in this routine, so R7-RD/RF are all free scratch;
; each field is read and stored to its own named memory global
; immediately, one at a time, rather than trying to hold several at
; once in registers -- there are seven fields and only six spare
; registers (R9/RA/RB/RC/RD/RF, since R7 holds the header buffer
; pointer and R8 is transient per-field scratch), so this isn't
; optional, but it also matches this project's own established style
; elsewhere (e.g. zvar_init) of storing each parameter immediately
; rather than juggling many live values in registers.
;

#include    include/opcodes.def

            extrn   zheader_initial_pc
            extrn   zheader_dictionary
            extrn   zheader_object_table
            extrn   zheader_globals
            extrn   zheader_dynamic_end
            extrn   zheader_high_memory
            extrn   zheader_abbrev_table

            proc    zheader_parse
            mov     r7, rd              ; r7 = header buffer base
                                        ; (survives -- no calls in
                                        ; this routine)
            ldn     r7
            xri     3
            lbnz    zhp_error           ; version != 3

            mov     r8, r7
            add16   r8, 4
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = high_memory
            mov     r8, zheader_high_memory
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 6
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = initial_pc
            mov     r8, zheader_initial_pc
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 8
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = dictionary
            mov     r8, zheader_dictionary
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 10
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = object_table
            mov     r8, zheader_object_table
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 12
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = globals
            mov     r8, zheader_globals
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 14
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = static_memory (this
                                        ; project's dynamic_end)
            mov     r8, zheader_dynamic_end
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     r8, r7
            add16   r8, 24
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = abbreviations
            mov     r8, zheader_abbrev_table
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

; ---- validation: mirrors host/story_header.c's own ordering checks.
; Every comparison below uses the same DF convention as everywhere
; else in this project: SM/SMB set DF=1 for NO borrow (minuend >=
; subtrahend). ----

; dynamic_end >= 64 (the header's own fixed size)
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            sub16   r9, 64
            lbnf    zhp_error           ; DF=0: dynamic_end < 64

; high_memory >= dynamic_end
            mov     r8, zheader_high_memory
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            sub16   r9, ra
            lbnf    zhp_error           ; DF=0: high_memory < dynamic_end

; object_table < dynamic_end
            mov     r8, zheader_object_table
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            sub16   r9, ra
            lbdf    zhp_error           ; DF=1: object_table >= dynamic_end

; globals >= 0x0c
            mov     r8, zheader_globals
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            sub16   r9, $0c
            lbnf    zhp_error           ; DF=0: globals < 0x0c

; globals < dynamic_end
            mov     r8, zheader_globals
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            sub16   r9, ra
            lbdf    zhp_error           ; DF=1: globals >= dynamic_end

; abbreviations < dynamic_end
            mov     r8, zheader_abbrev_table
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            sub16   r9, ra
            lbdf    zhp_error           ; DF=1: abbreviations >= dynamic_end

            clc
            rtn

zhp_error:
            stc
            rtn
            endp

            proc    _zheader_data
zheader_initial_pc:     dw      0
zheader_dictionary:     dw      0
zheader_object_table:   dw      0
zheader_globals:        dw      0
zheader_dynamic_end:    dw      0
zheader_high_memory:    dw      0
zheader_abbrev_table:   dw      0
                public  zheader_initial_pc
                public  zheader_dictionary
                public  zheader_object_table
                public  zheader_globals
                public  zheader_dynamic_end
                public  zheader_high_memory
                public  zheader_abbrev_table
            endp
