;
; zload.asm - V3 story file loader
;
; zload_story: RF = path string (a real filename -- ELF-DOS's own
; filesystem supports long filenames, no 8.3 truncation, so a story
; file's actual name, spaces and all, works directly). Opens the
; file, parses and validates its header (lib/zheader.asm), allocates
; and populates every resident buffer the interpreter needs from the
; program's own free RAM (lib/heap_bump.asm, sized from LOADER_ARGS'
; own mem_base/mem_top -- the caller must have called bump_init
; already), and initializes every VM subsystem from it: zminit,
; zstack_init, zvar_init, zobj_init, zdict_init, zcinit. Leaves the
; story's own FCB open on success (zcinit needs it for the rest of
; the run); closes it on any failure. Sets zdisp_pc/zdisp_pc_bank to
; the header's own initial_pc (always < 65536 on its own -- it's a
; plain header field, never a packed address). DF=1 on any failure
; (bad file, bad header, allocation failure, short read).
;
; Only the object table gets a REAL host pointer handed to its own
; init call (zobj_init) -- it's guaranteed to live in dynamic memory
; by the Z-machine standard (attributes/properties are writable), so
; it's physically inside the same buffer zminit itself uses. The
; dictionary is NOT guaranteed dynamic (it's read-only, and every real
; V3 file puts it in static memory -- see docs/ARCHITECTURE.md's own
; note and the zheader.asm fix from the same session that found this),
; so it can't share that buffer's own guest-address mapping; it gets
; its own dedicated resident buffer instead, sized to its actual
; computed table length (read via zmread_bytes, cache-aware, from
; wherever it really lives) rather than folded into the dynamic-memory
; region.
;
; zparse_init is deliberately NOT called here: zds_sread (lib/
; zdispatch.asm) already calls it itself, per sread invocation, using
; that call's own operand-supplied text/parse buffer addresses -- the
; loader has nothing to set up for it ahead of time.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zheader_parse
            extrn   zheader_initial_pc
            extrn   zheader_dictionary
            extrn   zheader_object_table
            extrn   zheader_globals
            extrn   zheader_dynamic_end
            extrn   zheader_abbrev_table

            extrn   zminit
            extrn   zstack_init
            extrn   zvar_init
            extrn   zobj_init
            extrn   zdict_init
            extrn   zcinit
            extrn   zmread_bytes

            extrn   bump_alloc
            extrn   bump_next
            extrn   bump_top

            extrn   zdisp_pc
            extrn   zdisp_pc_bank
            extrn   zdec_init

            extrn   zload_fcb
            extrn   zload_iobuf
            extrn   zload_cache_buf
            extrn   zload_header
            extrn   zload_dynbuf
            extrn   zload_framebuf
            extrn   zload_dict_prefix
            extrn   zload_dict_sepcount
            extrn   zload_dict_entrylen
            extrn   zload_dict_total
            extrn   zdi_scratch_dictbuf
            extrn   zload_fail_stage
            extrn   zload_fail_avail
            extrn   zload_fail_req

ZLOAD_STACK_SIZE:       equ     512     ; eval stack: 256 words --
                                        ; generous for any real V3
                                        ; expression depth
ZLOAD_FRAME_COUNT:      equ     16      ; max simultaneous call depth
ZLOAD_FRAME_SIZE:       equ     37      ; must match zvar.asm's own
                                        ; FRAME_SIZE
ZLOAD_DICT_PREFIX_LEN:  equ     16      ; generous: covers any real
                                        ; V3 dictionary's separator
                                        ; count (always small) plus
                                        ; entry_length/entry_count

            proc    zload_story
            mov     rd, zload_fcb
            mov     ra, zload_iobuf
            mov     r8, zload_fail_stage
            ldi     1                   ; stage 1: open
            str     r8
            ldi     0                   ; mode 0: read
            call    K_FILE_OPEN
            lbdf    zls_fail_noclose

            mov     rf, zload_header
            mov     rd, zload_fcb
            ldi     0
            phi     rc
            ldi     64
            plo     rc
            mov     r8, zload_fail_stage
            ldi     2                   ; stage 2: header read
            str     r8
            call    K_FILE_READ
            lbdf    zls_fail

            mov     rd, zload_header
            mov     r8, zload_fail_stage
            ldi     3                   ; stage 3: header validation
            str     r8
            call    zheader_parse
            lbdf    zls_fail

; ---- allocate and populate the resident dynamic-memory buffer ----
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     rc
            ldn     r8
            plo     rc                  ; rc = dynamic_end
            mov     r8, zload_fail_stage
            ldi     4                   ; stage 4: dynbuf alloc (OOM)
            str     r8
            call    bump_alloc
            glo     rf
            lbnz    zls_have_dynbuf
            ghi     rf
            lbnz    zls_have_dynbuf
            lbr     zls_fail            ; rf == 0: out of RAM
zls_have_dynbuf:
            mov     r9, zload_dynbuf
            ghi     rf
            str     r9
            inc     r9
            glo     rf
            str     r9                  ; zload_dynbuf = rf

            mov     rd, zload_fcb
            ldi     0
            plo     rc                  ; whence = SEEK_SET
            mov     ra, 0               ; offset high word
            mov     r9, 0               ; offset low word
            mov     r8, zload_fail_stage
            ldi     5                   ; stage 5: seek
            str     r8
            call    K_FILE_SEEK
            lbdf    zls_fail

            mov     r8, zload_dynbuf
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = dynbuf
            mov     rd, zload_fcb
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     rc
            ldn     r8
            plo     rc                  ; rc = dynamic_end
            mov     r8, zload_fail_stage
            ldi     6                   ; stage 6: dynbuf read
            str     r8
            call    K_FILE_READ
            lbdf    zls_fail

            mov     r8, zload_dynbuf
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = dynbuf
            mov     r8, zheader_dynamic_end
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = dynamic_end
            call    zminit

; ---- allocate and initialize the eval stack ----
            mov     rc, ZLOAD_STACK_SIZE
            mov     r8, zload_fail_stage
            ldi     7                   ; stage 7: eval stack alloc (OOM)
            str     r8
            call    bump_alloc
            glo     rf
            lbnz    zls_have_stack
            ghi     rf
            lbnz    zls_have_stack
            lbr     zls_fail
zls_have_stack:
            mov     rd, rf              ; rd = stack buffer start
            mov     rf, rd
            add16   rf, ZLOAD_STACK_SIZE ; rf = exclusive end
            call    zstack_init

; ---- allocate and initialize the call-frame stack ----
            mov     rc, 592             ; ZLOAD_FRAME_COUNT *
                                        ; ZLOAD_FRAME_SIZE
            mov     r8, zload_fail_stage
            ldi     8                   ; stage 8: frame stack alloc (OOM)
            str     r8
            call    bump_alloc
            glo     rf
            lbnz    zls_have_frames
            ghi     rf
            lbnz    zls_have_frames
            lbr     zls_fail
zls_have_frames:
            mov     r9, zload_framebuf
            ghi     rf
            str     r9
            inc     r9
            glo     rf
            str     r9                  ; zload_framebuf = rf

            mov     r8, zheader_globals
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = globals_base (guest addr)
            mov     r8, zload_framebuf
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = framebuf start
            mov     rc, rf
            add16   rc, 592            ; ZLOAD_FRAME_COUNT *
                                        ; ZLOAD_FRAME_SIZE
                                        ; rc = framebuf exclusive end
            call    zvar_init

; ---- object table: a real host pointer, physically inside dynbuf
; (guaranteed dynamic-resident by the Z-machine standard) ----
            mov     r8, zload_dynbuf
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = dynbuf (host base)
            mov     rf, rd              ; rf = zobj_init's own second
                                        ; argument: the host address
                                        ; guest address 0 maps to, which
                                        ; it needs to translate an object
                                        ; entry's property-table field
                                        ; (the one guest address stored
                                        ; inside the object table)
            mov     r8, zheader_object_table
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = object_table (guest
                                        ; offset, always < dynamic_end)
            add16   rd, r9              ; rd = real host address
            call    zobj_init

; ---- dictionary: NOT guaranteed resident in dynbuf (it's normally in
; static memory) -- fetch a generous prefix first, through zmread_bytes
; (cache-aware; the object/dynamic buffers aren't populated with
; static memory, so a real fetch through the story file itself is
; needed here even before zcinit runs, which is why zcinit is called
; further down but this fetch works anyway: at guest addresses below
; dynamic_end everything is already resident via zminit, and the
; dictionary is virtually always above it, in static memory -- exactly
; the case zmread's own cache fallback exists for, and it works with
; no cache configured yet the same way it always has: DF=1 if zcfcb
; is still 0. So the dictionary prefix/table fetch below must happen
; AFTER zcinit, not before -- reordered accordingly.) ----
            mov     rd, zload_fcb
            mov     rf, zload_cache_buf
            call    zcinit

            mov     r8, zheader_dictionary
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = dictionary guest addr
                                        ; (always a plain 16-bit header
                                        ; field, never packed)
            mov     ra, 0               ; address high word
            mov     rf, zload_dict_prefix
            mov     rc, ZLOAD_DICT_PREFIX_LEN
            mov     r8, zload_fail_stage
            ldi     9                   ; stage 9: dict prefix read
            str     r8
            call    zmread_bytes
            lbdf    zls_fail

            ; zmread_bytes's own contract: DF=0 with RC short of what
            ; was asked for is a NORMAL result for a caller with no
            ; prior length measurement, not a failure -- but this
            ; caller measures entry_length/entry_count straight out of
            ; the prefix buffer right below, so anything less than the
            ; full ZLOAD_DICT_PREFIX_LEN bytes leaves the unfilled tail
            ; as stale/uninitialized memory, silently misread as real
            ; header fields. Must be exact.
            ghi     rc
            lbnz    zls_fail            ; can't legitimately exceed 255
                                        ; for a 16-byte request
            glo     rc
            xri     ZLOAD_DICT_PREFIX_LEN
            lbnz    zls_fail            ; short read: something is
                                        ; wrong, not a normal partial
                                        ; result

            ; BUG FIX: the destination pointer is set up FIRST here,
            ; and the byte loaded LAST -- "mov r9, <label>" ends in an
            ; "ldi <label low byte> / plo r9", so it CLOBBERS D (this
            ; project's own toolchain gotcha #2). With the mov sitting
            ; between the ldn and the str, both zload_dict_sepcount and
            ; RA got the low byte of zload_dict_sepcount's own ADDRESS
            ; instead of the separator count -- which then indexed the
            ; entry_length/entry_count reads below clean off the end of
            ; the 16-byte prefix buffer, so the dictionary size came out
            ; as garbage (37897 bytes rather than ZORK I's real 4886)
            ; and stage 10 failed as a bogus OOM.
            mov     r9, zload_dict_sepcount
            mov     r8, zload_dict_prefix
            ldn     r8                  ; d = separator count
            str     r9                  ; zload_dict_sepcount = d
            plo     ra
            ldi     0
            phi     ra                  ; ra = 0:sep_count

            mov     r8, zload_dict_prefix
            add16   r8, ra
            inc     r8                  ; r8 = &entry_length (prefix +
                                        ; 1 + sep_count)
            mov     r9, zload_dict_entrylen ; pointer first, byte
                                        ; last -- same D-clobber fix as
                                        ; the separator count above
            ldn     r8                  ; d = entry_length
            str     r9                  ; zload_dict_entrylen = d
            inc     r8                  ; r8 = &entry_count

            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = entry_count (raw, signed)

            ghi     r9
            ani     $80
            lbz     zls_dict_positive
            ghi     r9
            not
            phi     r9
            glo     r9
            not
            plo     r9
            add16   r9, 1               ; r9 = |entry_count|
zls_dict_positive:

; total = 4 + sep_count + |entry_count| * entry_length -- entry_length
; is a byte (0-255 in principle, always small in every real V3 file),
; so a simple repeated-add loop is simpler than a general multiply
            mov     rb, zload_dict_total
            ldi     0
            str     rb
            inc     rb
            ldi     0
            str     rb                  ; zload_dict_total = 0

            mov     r8, zload_dict_entrylen
            ldn     r8
            plo     r7                  ; r7.0 = entry_length (loop
                                        ; countdown)
zls_dict_mul_loop:
            glo     r7
            lbz     zls_dict_mul_done
            mov     rb, zload_dict_total
            lda     rb
            phi     ra
            ldn     rb
            plo     ra                  ; ra = running total
            add16   ra, r9              ; ra += |entry_count|
            mov     rb, zload_dict_total
            ghi     ra
            str     rb
            inc     rb
            glo     ra
            str     rb
            dec     r7
            lbr     zls_dict_mul_loop
zls_dict_mul_done:

            mov     r8, zload_dict_total
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = |entry_count|*entry_length
            add16   ra, 4
            mov     r8, zload_dict_sepcount
            ldn     r8
            plo     r9
            ldi     0
            phi     r9
            add16   ra, r9              ; ra = total dictionary size
            mov     r8, zload_dict_total
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zload_dict_total = total size

            mov     rc, ra
            mov     r8, zload_fail_stage
            ldi     10                  ; stage 10: dictionary alloc (OOM)
            str     r8
            call    bump_alloc
            glo     rf
            lbnz    zls_have_dictbuf
            ghi     rf
            lbnz    zls_have_dictbuf
            mov     rf, bump_top
            lda     rf
            phi     r8
            ldn     rf
            plo     r8                  ; r8 = bump_top
            mov     rf, bump_next
            lda     rf
            phi     r9
            ldn     rf
            plo     r9                  ; r9 = bump_next
            mov     rb, r8
            sub16   rb, r9              ; rb = bump_top - bump_next
                                        ; (remaining, same inclusive-
                                        ; bounds convention as bump_
                                        ; alloc's own header)
            mov     r8, zload_fail_avail
            ghi     rb
            str     r8
            inc     r8
            glo     rb
            str     r8                  ; zload_fail_avail = rb
            mov     r8, zload_fail_req
            ghi     rc
            str     r8
            inc     r8
            glo     rc
            str     r8                  ; zload_fail_req = rc (bump_
                                        ; alloc's own header documents
                                        ; rc as unmodified on failure)
            lbr     zls_fail
zls_have_dictbuf:
            mov     r9, zdi_scratch_dictbuf
            ghi     rf
            str     r9
            inc     r9
            glo     rf
            str     r9                  ; stash the dictionary buffer
                                        ; pointer -- reused immediately
                                        ; below, kept in memory rather
                                        ; than a register across the
                                        ; zmread_bytes call that follows

            mov     r8, zheader_dictionary
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = dictionary guest addr
            mov     ra, 0
            mov     r8, zdi_scratch_dictbuf
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = dictionary buffer
            mov     r8, zload_dict_total
            lda     r8
            phi     rc
            ldn     r8
            plo     rc                  ; rc = total dictionary size
            mov     r8, zload_fail_stage
            ldi     11                  ; stage 11: dictionary table read
            str     r8
            call    zmread_bytes
            lbdf    zls_fail

            ; same exact-count requirement as the prefix fetch above --
            ; zdict_init below trusts every byte of this buffer is real
            ; story data, not leftover garbage from a short read
            mov     r8, zload_dict_total
            lda     r8
            str     r2
            ghi     rc
            xor
            lbnz    zls_fail
            ldn     r8
            str     r2
            glo     rc
            xor
            lbnz    zls_fail

            mov     r8, zheader_dictionary
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = the dictionary's GUEST
                                        ; address -- zdict_init needs it
                                        ; alongside the real one, since
                                        ; this buffer is a dedicated
                                        ; allocation with no zmbase
                                        ; relationship to guest space
            mov     r8, zdi_scratch_dictbuf
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = dictionary buffer (real
                                        ; host pointer)
            call    zdict_init

; ---- abbreviation table (guest address, resolved lazily through
; zmread by zdec.asm itself -- no resident buffer needed here) ----
            mov     r8, zheader_abbrev_table
            lda     r8
            phi     rd
            ldn     r8
            plo     rd
            call    zdec_init

; ---- initial pc: always a plain 16-bit header field, never packed,
; so bank 0 is always correct here ----
            mov     r8, zheader_initial_pc
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zdisp_pc
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8
            mov     r8, zdisp_pc_bank
            ldi     0
            str     r8

            clc
            rtn

zls_fail:
            mov     rd, zload_fcb
            call    K_FILE_CLOSE        ; best-effort; df ignored
zls_fail_noclose:
            stc
            rtn
            endp

            proc    _zload_data
zload_fcb:              ds      FCB_LEN
zload_iobuf:             ds      FCB_IOBUF_LEN
zload_cache_buf:         ds      512
zload_header:            ds      64
zload_dynbuf:            dw      0
zload_framebuf:          dw      0
zload_dict_prefix:       ds      ZLOAD_DICT_PREFIX_LEN
zload_dict_sepcount:     db      0
zload_dict_entrylen:     db      0
zload_dict_total:        dw      0
zdi_scratch_dictbuf:     dw      0
zload_fail_stage:        db      0   ; which fallible step failed (see zrun3_main.asm's zrun3_load_fail)
zload_fail_avail:        dw      0   ; bump_top-bump_next at an OOM
                                    ; failure (currently only set at
                                    ; the dictionary allocation, stage
                                    ; 10 -- add to the other 3 bump_
                                    ; alloc sites too if one of THEM
                                    ; ever OOMs instead)
zload_fail_req:          dw      0   ; the size that OOM'd
                public  zload_fcb
                public  zload_iobuf
                public  zload_cache_buf
                public  zload_header
                public  zload_dynbuf
                public  zload_framebuf
                public  zload_dict_prefix
                public  zload_dict_sepcount
                public  zload_dict_entrylen
                public  zload_dict_total
                public  zdi_scratch_dictbuf
                public  zload_fail_stage
                public  zload_fail_avail
                public  zload_fail_req
            endp
