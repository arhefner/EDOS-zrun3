;
; zmcachediag.asm - real-file diagnostic for zmread's cache-fallback
; path (lib/zmem.asm)
;
; Unlike every other diag/*.asm here, this one is NOT kernel-
; independent: the bug it exercises only exists in zmread's own
; zcread-backed cache path, which requires a genuinely open FCB (per
; zcinit's own documented contract, and per the zcfcb==0 guard added
; after the zcache wild-pointer incident -- a fabricated/fake FCB
; would recreate that exact hazard rather than test around it). So
; this diag creates its own small scratch file, writes known bytes
; into it, reopens it read-only, and drives zcinit/zmread against the
; real kernel file path, the same way an eventual ELF-DOS interpreter
; front end will.
;
; check 0 exercises the actual regression: zmread's cache path used to
; clobber RD (reusing it to hold zcread's own 32-bit-offset high word)
; while its resident path left RD alone, so any caller advancing its
; own cursor with a bare `inc rd` after the call -- exactly
; lib/zdecode.asm's zde_read_byte, used for every single instruction/
; operand byte fetched -- would silently corrupt that cursor the
; moment a fetch landed in cache-backed memory. This reproduces
; zde_read_byte's own idiom directly against zmread: four consecutive
; guest addresses beyond the resident region, `inc rd` between each
; read, asserting each byte matches the real file's own content at
; that offset (zmread_cache's offset convention is that guest address
; N reads file offset N directly when zm_bank is 0). If RD were still
; getting clobbered, the second read onward would silently re-read
; from the (wrong) resident region instead of advancing through the
; file.
;
; check 1 is a regression guard: resident reads/writes below the
; dynamic end still work correctly with a cache configured alongside
; them (zminit's own region is untouched by any of this).
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zminit
            extrn   zmread
            extrn   zmwrite
            extrn   zcinit

            extrn   zmc_mem_buf
            extrn   zmc_cache_buf
            extrn   zmc_fcb
            extrn   zmc_iobuf
            extrn   zmc_path
            extrn   zmc_filedata
            extrn   zmc_results

ZMCACHE_COUNT:  equ     2

; zmcache_run: no arguments. Returns RF = number of failed checks,
; DF=1 if RF != 0. zmc_results[0..ZMCACHE_COUNT-1] holds one byte per
; check (0 = pass, 1 = fail).
            proc    zmcache_run
            mov     rd, zmc_mem_buf
            mov     rf, 4
            call    zminit              ; dynamic guest addresses 0..3
                                        ; resident; 4+ falls through to
                                        ; the cache

; ---- create/truncate the scratch file and write its known content ----
            mov     rf, zmc_path
            mov     rd, zmc_fcb
            mov     ra, zmc_iobuf
            ldi     1                   ; mode 1: create/overwrite
            call    K_FILE_OPEN
            lbdf    zmc_setup_fail

            mov     rf, zmc_filedata
            mov     rd, zmc_fcb
            ldi     0
            phi     rc
            ldi     8
            plo     rc
            call    K_FILE_WRITE
            lbdf    zmc_setup_fail_close

            mov     rd, zmc_fcb
            call    K_FILE_CLOSE
            lbdf    zmc_setup_fail

; ---- reopen read-only and hand the FCB to zcinit ----
            mov     rf, zmc_path
            mov     rd, zmc_fcb
            mov     ra, zmc_iobuf
            ldi     0                   ; mode 0: read
            call    K_FILE_OPEN
            lbdf    zmc_setup_fail

            mov     rd, zmc_fcb
            mov     rf, zmc_cache_buf
            call    zcinit

; ---- check 0: cursor survives consecutive cache-backed reads ----
            mov     rd, 4
            call    zmread              ; expect d=$aa, df=0
            lbdf    zc0_fail
            xri     $aa
            lbnz    zc0_fail

            inc     rd                  ; the exact idiom
                                        ; zde_read_byte uses -- only
                                        ; correct if zmread left rd
                                        ; alone
            call    zmread              ; expect d=$bb
            lbdf    zc0_fail
            xri     $bb
            lbnz    zc0_fail

            inc     rd
            call    zmread              ; expect d=$cc
            lbdf    zc0_fail
            xri     $cc
            lbnz    zc0_fail

            inc     rd
            call    zmread              ; expect d=$dd
            lbdf    zc0_fail
            xri     $dd
            lbnz    zc0_fail

            mov     rb, zmc_results+0
            ldi     0
            lbr     zc0_store
zc0_fail:   mov     rb, zmc_results+0
            ldi     1
zc0_store:  str     rb

; ---- check 1: resident reads/writes still work with a cache
; configured alongside them ----
            mov     rd, 1
            ldi     $5a
            call    zmwrite
            lbdf    zc1_fail
            mov     rd, 1
            call    zmread
            lbdf    zc1_fail
            xri     $5a
            lbnz    zc1_fail

            mov     rb, zmc_results+1
            ldi     0
            lbr     zc1_store
zc1_fail:   mov     rb, zmc_results+1
            ldi     1
zc1_store:  str     rb

            mov     rd, zmc_fcb
            call    K_FILE_CLOSE        ; best-effort; df ignored
            mov     rf, zmc_path
            call    K_FILE_DELETE       ; best-effort; df ignored

; tally failures into RF, DF=1 if any
            mov     rb, zmc_results
            ldi     ZMCACHE_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zmc_tally:
            lda     rb
            lbz     zmc_tally_next
            inc     rf
zmc_tally_next:
            dec     r9
            glo     r9
            lbnz    zmc_tally
            glo     rf
            lbnz    zmc_fail_return
            clc
            rtn
zmc_fail_return:
            stc
            rtn

zmc_setup_fail_close:
            mov     rd, zmc_fcb
            call    K_FILE_CLOSE        ; best-effort; df ignored
zmc_setup_fail:
; setup itself failed (file create/write/reopen) -- mark both checks
; failed and bail without touching zcinit/zmread at all
            mov     rb, zmc_results+0
            ldi     1
            str     rb
            mov     rb, zmc_results+1
            ldi     1
            str     rb
            mov     rf, 2
            stc
            rtn
            endp

            proc    _zmcachediag_data
zmc_mem_buf:    ds      4
zmc_cache_buf:  ds      512
zmc_fcb:        ds      FCB_LEN
zmc_iobuf:      ds      FCB_IOBUF_LEN
zmc_path:       db      "ZMCACHE.TST",0
zmc_filedata:   db      0,0,0,0,$aa,$bb,$cc,$dd
zmc_results:    ds      ZMCACHE_COUNT
                public  zmc_mem_buf
                public  zmc_cache_buf
                public  zmc_fcb
                public  zmc_iobuf
                public  zmc_path
                public  zmc_filedata
                public  zmc_results
            endp
