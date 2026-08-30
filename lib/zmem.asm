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
            mov     r7, rd
            add16   r7, 1               ; r7 = the low byte's address
                                        ; -- untouched by zmread, so it
                                        ; survives both calls below
            call    zmread              ; d = high byte (rd unchanged)
            lbdf    zmr16_fail
            plo     rc                  ; rc.0 = high byte -- rc is
                                        ; untouched by zmread too

            mov     rd, r7
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

            proc    _zmem_data
zmbase:     dw      0
zmend:      dw      0
zm_bank:    db      0       ; zmread's own implicit high word for its
                            ; cache fallback -- see this file's own
                            ; header for who sets/resets it and why
            public  zmbase
            public  zmend
            public  zm_bank
            endp
