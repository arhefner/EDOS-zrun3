;
; zmem.asm - resident dynamic-memory access for the Z-machine, with a
; file-backed fallback (lib/zcache.asm) for everything beyond it
;
; zmwrite never falls back to the cache -- static and high memory are
; read-only by the Z-machine spec, so a write beyond zmend staying an
; honest DF=1 is correct, not a missing feature.
;
; Both zmread's and zmread_wide's own cache paths first check zcfcb
; (lib/zcache.asm's own FCB pointer field) for nonzero, and cleanly
; return DF=1 instead of calling zcread at all when it's still 0 --
; i.e. zcinit was never called. This matters: every bare-metal diag in
; this project deliberately never touches the kernel, so zcfcb sits at
; its zeroed default in every one of them, and an out-of-range read
; (which several diag checks exercise on purpose, expecting a clean
; DF=1) used to be perfectly safe. Without this guard, that same read
; would drive K_FILE_SEEK/K_FILE_READ with a garbage FCB pointer --
; a real wild kernel call, not a hypothetical one: this is exactly
; what crashed real ELF-DOS hardware (a second diag run corrupted
; enough state that the shell itself came back "not found or invalid"
; and the machine had to be power-cycled) before this guard existed.
;
; zmread's own fallback only ever reaches the FIRST 64K of the story
; (its own RD parameter is a 16-bit guest address, and it always uses
; zm_bank -- 0 unless a caller explicitly sets it -- as the fallback's
; implicit high word). Every existing caller (direct byte/word operand
; addresses, globals) is safe with that: those are all guaranteed
; 16-bit by the Z-machine spec itself. The one caller that legitimately
; needs to reach past 64K is zdisp_step's own instruction-byte fetch,
; when the current PC's own high word is nonzero -- it sets zm_bank
; immediately before decoding and resets it to 0 immediately after
; (see zdispatch.asm's own note at that call site). Packed-address text
; staging (print_paddr and friends) goes through zmread_wide below
; instead, with the full 32-bit offset explicit in every call, needing
; no shared state at all.
;

#include    include/opcodes.def

            extrn   zmbase
            extrn   zmend
            extrn   zm_bank
            extrn   zm_saved_addr
            extrn   zmr16_addr
            extrn   zmb_addr
            extrn   zmb_addr_hi
            extrn   zmb_dest
            extrn   zmb_count
            extrn   zmb_orig_count

            extrn   zmread
            extrn   zmread_wide
            extrn   zmwrite

            extrn   zcread
            extrn   zcfcb

; zminit: RD = host RAM base, RF = exclusive guest dynamic end.
            proc    zminit
            mov     rb, zmbase
            ghi     rd
            str     rb
            inc     rb
            glo     rd
            str     rb
            mov     rb, zmend
            ghi     rf
            str     rb
            inc     rb
            glo     rf
            str     rb
            clc
            rtn
            endp

; zmread: RD = guest address, returns D = byte. DF=1 only for a
; genuine cache miss/I/O failure now -- an out-of-resident-range
; address falls back to zcache (see this file's own header for the
; zm_bank convention that governs it) rather than failing outright.
            proc    zmread
; BUG FIX: the resident-vs-cache decision has to consider zm_bank
; FIRST. Resident dynamic memory is, by definition, the story's first
; zmend bytes -- so a nonzero bank means this address cannot possibly
; be resident no matter how small its own 16 bits are, and comparing
; only those 16 bits against zmend sent it to dynbuf instead. Any
; routine living past 64K whose offset within its bank happens to fall
; below zmend then decoded as whatever dynamic memory held at the same
; 16-bit address: ZORK I's mailbox handler is at bank 1 offset $01EB,
; well under its $2E53 dynamic end, so opening the mailbox executed
; the abbreviation table as code.
            mov     rb, zm_bank
            ldn     rb
            lbnz    zmread_cache        ; bank != 0: never resident

            mov     rb, zmend
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, rd
            sub16   rb, r8              ; rb = address - zmend; the 1802's
                                        ; SM/SMB set DF=1 for NO borrow
                                        ; (minuend >= subtrahend), so DF=1
                                        ; here means address >= zmend --
                                        ; out of range
            lbdf    zmread_cache
            mov     rf, zmbase
            lda     rf
            phi     r9
            ldn     rf
            plo     r9
            mov     rf, rd
            add16   rf, r9
            ldn     rf
            clc
            rtn

zmread_cache:
            mov     r8, zcfcb
            lda     r8
            lbnz    zmread_cache_go
            ldn     r8
            lbz     zmrf                ; zcfcb == 0: the cache was
                                        ; never initialized (zcinit not
                                        ; called -- true of every bare-
                                        ; metal diag, which never
                                        ; touches the kernel at all).
                                        ; Calling zcread anyway would
                                        ; drive K_FILE_SEEK/K_FILE_READ
                                        ; with a garbage FCB pointer --
                                        ; a real wild kernel call, not
                                        ; a hypothetical one (this
                                        ; crashed real ELF-DOS hardware
                                        ; before this guard existed).
                                        ; Fall back to the old, safe
                                        ; DF=1 instead.
zmread_cache_go:
            mov     r8, zm_saved_addr
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8                  ; stash the original guest
                                        ; address in memory, not a
                                        ; register -- zcread (and
                                        ; whatever K_FILE_* it may call
                                        ; internally on a cache miss)
                                        ; has no clobber list broad
                                        ; enough to trust any register
                                        ; surviving it, matching the
                                        ; K_FILE_READ precedent already
                                        ; hit once in zdisp_restore_game

            mov     r8, zm_bank
            ldn     r8
            plo     r9
            ldi     0
            phi     r9                  ; r9 = 0:zm_bank -- this
                                        ; read's own 32-bit offset high
                                        ; word (0 unless a caller
                                        ; explicitly set zm_bank first)
            mov     rf, rd              ; rf = the original guest
                                        ; address (this read's own
                                        ; low word)
            mov     rd, r9              ; rd = high word
            call    zcread              ; d = byte, df = eof/io
                                        ; failure

            plo     r9                  ; r9.0 = the byte, stashed --
                                        ; plo (like str) never touches
                                        ; d or df, so this is safe to
                                        ; do before the reload below
                                        ; even though d/df must both
                                        ; still reach the caller
                                        ; unharmed
            mov     r8, zm_saved_addr
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = the original guest
                                        ; address, restored -- none of
                                        ; mov/lda/ldn/phi/plo touch df,
                                        ; so zcread's own df is still
                                        ; intact here
            glo     r9                  ; d = the byte, reloaded
            rtn
zmrf:
            stc
            rtn
            endp

; zmread_wide: RD = 32-bit guest/story offset's high word, RF = low
; word (set immediately before the call). Returns D = byte, DF=1 on
; failure. For addresses that may genuinely exceed 16 bits (packed-
; address text staging) -- unlike zmread, never consults zm_bank,
; since the caller already has the full offset in hand.
            proc    zmread_wide
            ghi     rd
            lbnz    zmwide_cache        ; high word nonzero: definitely
                                        ; beyond 16-bit resident range
            glo     rd
            lbnz    zmwide_cache

            mov     rd, rf              ; high word is 0: this is
                                        ; really just a 16-bit address
                                        ; -- reuse zmread's own
                                        ; resident-vs-cache logic
                                        ; directly (safe: zm_bank is
                                        ; always 0 outside zdisp_step's
                                        ; own narrow decode window,
                                        ; and this routine is never
                                        ; called from within that
                                        ; window)
            call    zmread
            rtn

zmwide_cache:
            mov     r8, zcfcb
            lda     r8
            lbnz    zmwide_cache_go
            ldn     r8
            lbz     zmwide_fail         ; zcfcb == 0: cache never
                                        ; initialized -- see zmread's
                                        ; own note at zmread_cache
zmwide_cache_go:
            call    zcread              ; definitely non-resident;
                                        ; read via the cache using the
                                        ; caller's own full offset
                                        ; directly, ignoring zmend
            rtn
zmwide_fail:
            stc
            rtn
            endp

; zmread16: RD = guest address. Returns RF = big-endian word (the
; format every V3 word field -- globals, property values, branch/call
; addresses -- is actually stored in). DF=1 if either byte is non-
; resident (the high byte is checked first; on DF=1 from that byte,
; the low byte is never read).
            proc    zmread16
; BUG FIX: the low byte's address used to live in R7 across the first
; zmread call, on the strength of "untouched by zmread". That was true
; when zmread only ever read resident memory -- it stopped being true
; the moment zmread grew its zcache fallback, which reaches
; K_FILE_SEEK/K_FILE_READ and clobbers essentially everything. The
; symptom was subtle because it only bites when the FIRST byte's own
; read misses the cache window: the high byte came back correct (RC is
; stashed after the call, so it really is safe) while the low byte was
; read from a garbage address. ZORK I's verb dispatch loads a routine
; address out of a static-memory table this way -- one word came back
; $4500 instead of $4552, and the game called into the middle of
; nothing. Memory, not a register, exactly as zmread_cache_go's own
; zm_saved_addr already does for the same reason.
            mov     r7, rd
            add16   r7, 1
            mov     r8, zmr16_addr
            ghi     r7
            str     r8
            inc     r8
            glo     r7
            str     r8                  ; zmr16_addr = the low byte's
                                        ; address
            call    zmread              ; d = high byte (rd unchanged)
            lbdf    zmr16_fail
            plo     rc                  ; rc.0 = high byte -- safe: rc
                                        ; is loaded AFTER the call

            mov     r8, zmr16_addr
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = the low byte's address
            call    zmread              ; d = low byte
            lbdf    zmr16_fail
            plo     rf                  ; rf.0 = low byte
            glo     rc
            phi     rf                  ; rf.1 = high byte -- rf is
                                        ; now the assembled word
            clc
            rtn
zmr16_fail:
            stc
            rtn
            endp

; zmwrite16: RD = guest address, RF = big-endian word. DF=1 if either
; byte is non-resident (the high byte is checked/written first; on
; DF=1 from that byte, the low byte is never touched).
            proc    zmwrite16
            mov     r7, rd
            add16   r7, 1               ; r7 = the low byte's address --
                                        ; untouched by zmwrite, so it
                                        ; survives both calls below
            ghi     rf
            plo     rc                  ; rc.0 = high byte
            glo     rf
            phi     rc                  ; rc.1 = low byte -- rc is also
                                        ; untouched by zmwrite, so both
                                        ; bytes survive its first call
                                        ; below even though that call's
                                        ; own RF.0 parameter overwrites
                                        ; the original rf

            glo     rc
            plo     rf
            call    zmwrite             ; writes the high byte at rd
                                        ; (the original address)
            lbdf    zmw16_fail

            mov     rd, r7
            ghi     rc
            plo     rf
            call    zmwrite             ; writes the low byte at r7
            lbdf    zmw16_fail
            clc
            rtn
zmw16_fail:
            stc
            rtn
            endp

; zmwrite: RD = guest address, RF.0 = byte. DF=1 if non-resident.
            proc    zmwrite
            plo     r9
            mov     rb, zmend
            lda     rb
            phi     r8
            ldn     rb
            plo     r8
            mov     rb, rd
            sub16   rb, r8              ; rb = address - zmend; DF=1 (no
                                        ; borrow) means address >= zmend --
                                        ; out of range (see zmread)
            lbdf    zmwf
            mov     rf, zmbase
            lda     rf
            phi     r8
            ldn     rf
            plo     r8
            mov     rf, rd
            add16   rf, r8
            glo     r9
            str     rf
            clc
            rtn
zmwf:
            stc
            rtn
            endp

; zmread_bytes: RD = guest address (low word), RF = destination
; buffer, RC = requested count, RA = guest address's high word (set
; immediately before the call; 0 for every plain 16-bit caller -- only
; a wide caller, e.g. print_paddr/call's own packed-address unpacking,
; which can legitimately need to address past 65535 in a V3 story file
; over 64K, ever passes anything else here). Copies up to COUNT bytes
; from guest memory (resident or cache-backed, via zmread_wide, which
; transparently degrades to plain zmread's own logic when the high
; word is 0) into the destination buffer, returning RC = the actual
; number of bytes copied. DF=1 ONLY if the very first byte failed (a
; genuinely bad starting address) -- running out of readable story
; data partway through is treated as a normal, expected stop (DF=0, RC
; less than requested), not a failure: a caller with no prior length
; measurement (print_addr/print_paddr's own generous fixed cap, or an
; abbreviation's own unmeasured text) deliberately asks for more than
; a story file may have left near its own end, and wants to decode
; whatever real bytes it actually got rather than fail outright the
; way an earlier version of this routine did (that version's own
; all-or-nothing contract made print_paddr/print_addr fail for any
; text without 512 bytes of valid story data after it -- caught by a
; hardware hang, not a review, when a short test file made every
; remaining zcache window refill land exactly on that boundary; see
; this file's own zcread fix from the same incident for the other half
; of it). A caller needing an EXACT count instead (decode_instruction's
; own inline-text length, already measured via zmread) must compare
; the returned RC against what it asked for itself -- a short result
; there means something more is wrong. Originally lived in
; lib/zdispatch.asm (as zdisp_fetch_guest_bytes, print-pipeline-only);
; moved here, renamed, once lib/zdec.asm also needed guest-byte fetch
; for abbreviation expansion and zdec.asm can't depend on zdispatch.asm
; without a layering cycle (zdispatch.asm is the one that calls INTO
; zdec.asm, not the reverse). Deliberately keeps its own running
; address/destination/remaining-count in memory (zmb_addr/_dest/
; _count/_orig_count) rather than any register: zmread's cache path
; may reach K_FILE_* calls internally on a cache miss, and those have
; no clobber footprint documented beyond their own RD/RF/RC inputs
; (see this file's own zmread_cache_go fix and its header comment for
; the same lesson learned once already, in zdisp_restore_game) --
; nothing this loop needs across the zmread call below can be trusted
; to survive in a register.
            proc    zmread_bytes
            mov     r8, zmb_addr
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8
            mov     r8, zmb_addr_hi
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8
            mov     r8, zmb_dest
            ghi     rf
            str     r8
            inc     r8
            glo     rf
            str     r8
            mov     r8, zmb_count
            ghi     rc
            str     r8
            inc     r8
            glo     rc
            str     r8
            mov     r8, zmb_orig_count
            ghi     rc
            str     r8
            inc     r8
            glo     rc
            str     r8

zmb_loop:
            mov     r8, zmb_count
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = remaining count
            glo     r9
            lbnz    zmb_have
            ghi     r9
            lbz     zmb_done
zmb_have:
            mov     r8, zmb_addr_hi
            lda     r8
            phi     rd
            ldn     r8
            plo     rd                  ; rd = current address's high
                                        ; word (0 for every existing
                                        ; caller -- only wide callers,
                                        ; e.g. print_paddr/call's own
                                        ; packed-address unpacking, ever
                                        ; set this nonzero)
            mov     r8, zmb_addr
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = current address's low
                                        ; word -- both reloaded fresh
                                        ; right before the call, the
                                        ; one thing that must be live
                                        ; in registers, since they're
                                        ; zmread_wide's own inputs

            call    zmread_wide         ; d = byte, df = err -- zero
                                        ; high word transparently
                                        ; degrades to zmread's own
                                        ; plain resident-or-cache
                                        ; logic (see zmread_wide's own
                                        ; header)
            lbdf    zmb_stop
            plo     r9                  ; r9.0 = the byte -- plo (unlike
                                        ; the lda/ldn just below) doesn't
                                        ; touch d, so stashing it here
                                        ; first survives the destination-
                                        ; pointer reload that follows

            mov     r8, zmb_dest
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = current destination
                                        ; pointer (r9 is where the byte
                                        ; itself lives now, so this
                                        ; reload uses ra instead)
            glo     r9                  ; d = the byte, reloaded
            str     ra                  ; write it
            inc     ra
            mov     r8, zmb_dest
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zmb_dest += 1

            mov     r8, zmb_addr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            add16   r9, 1               ; r9 = addr_lo+1; DF=1 iff this
                                        ; wrapped past 0xffff (add16's
                                        ; own carry-out from its high-
                                        ; byte ADC, same as any multi-
                                        ; precision addition's overall
                                        ; carry)
            mov     r8, zmb_addr
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zmb_addr += 1 (wrapped)
            lbnf    zmb_no_carry
            mov     r8, zmb_addr_hi
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            add16   r9, 1
            mov     r8, zmb_addr_hi
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zmb_addr_hi += 1 -- the low
                                        ; word just wrapped past a 64K
                                        ; boundary
zmb_no_carry:

            mov     r8, zmb_count
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            sub16   r9, 1
            mov     r8, zmb_count
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zmb_count -= 1

            lbr     zmb_loop

zmb_done:
; full success: rc = the original requested count, reloaded fresh
; rather than trusted to have survived the loop's own many zmread
; calls
            mov     r8, zmb_orig_count
            lda     r8
            phi     rc
            ldn     r8
            plo     rc
            clc
            rtn

zmb_stop:
; a zmread call failed partway through -- copied = orig_count -
; remaining (the count that was still waiting to be attempted at the
; point of failure)
            mov     r8, zmb_orig_count
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = original requested count
            mov     r8, zmb_count
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = remaining count at the
                                        ; point of failure
            mov     rc, r9
            sub16   rc, ra              ; rc = copied so far

            glo     rc
            lbnz    zmb_partial
            ghi     rc
            lbnz    zmb_partial
            stc                         ; copied == 0: the very first
                                        ; byte failed -- a real error
            rtn

zmb_partial:
            clc                         ; copied > 0: a normal, expected
                                        ; early stop
            rtn
            endp

            proc    _zmem_data
zmbase:     dw      0
zmend:      dw      0
zm_bank:    db      0       ; zmread's own implicit high word for its
                            ; cache fallback -- see this file's own
                            ; header for who sets/resets it and why
zm_saved_addr: dw   0       ; zmread's own scratch, used only to
                            ; survive its own call to zcread on the
                            ; cache path -- see zmread_cache_go's own
                            ; comment
zmr16_addr:    dw   0       ; zmread16's own scratch, for the same
                            ; reason as zm_saved_addr above: nothing in
                            ; a register survives zmread's cache path
zmb_addr:      dw   0       ; zmread_bytes' own loop state, kept in
                            ; memory rather than any register -- see
                            ; its own header comment
zmb_addr_hi:   dw   0       ; the address's high word -- 0 for every
                            ; caller except a wide one (print_paddr/
                            ; call's own packed-address unpacking)
zmb_dest:      dw   0
zmb_count:     dw   0       ; remaining (not yet attempted) count --
                            ; decremented in place
zmb_orig_count: dw  0       ; the count originally requested, kept
                            ; separately so the actual-bytes-copied
                            ; total can still be computed after a stop
            public  zmbase
            public  zmend
            public  zm_bank
            public  zm_saved_addr
            public  zmr16_addr
            public  zmb_addr
            public  zmb_addr_hi
            public  zmb_dest
            public  zmb_count
            public  zmb_orig_count
            endp
