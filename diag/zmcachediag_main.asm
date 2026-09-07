;
; zmcachediag_main.asm - ELF-DOS front end for the zmread cache-
; fallback diagnostics
;
; Usage: ZMCACHEDIAG
;
; Runs zmcachediag.asm's zmcache_run against zmread's real, kernel-
; file-backed cache path (lib/zmem.asm + lib/zcache.asm) and reports
; PASS/FAIL per check plus a summary line, all through the ELF-DOS
; kernel's console output calls. Unlike the other diag/*.asm front
; ends, this one genuinely needs the real kernel filesystem (creates
; and deletes its own small scratch file) -- see zmcachediag.asm's own
; header for why.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zmcache_run
            extrn   zmc_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zmcache_run         ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zmc_note_failure
            mov     rd, zmc_had_failure
            ldi     0
            lbr     zmc_store_flag
zmc_note_failure:
            mov     rd, zmc_had_failure
            ldi     1
zmc_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (cursor survives consecutive cache-backed reads): ",0
            mov     rb, zmc_results+0
            call    zmc_report

            call    K_INMSG
            db      "check 1 (resident reads/writes alongside a cache): ",0
            mov     rb, zmc_results+1
            call    zmc_report

            mov     rf, zmc_had_failure
            ldn     rf
            lbnz    zmc_some_failed

            call    K_INMSG
            db      "All 2 checks passed.",13,10,0
            ldi     0
            lbr     zmc_exit

zmc_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zmc_exit:
            rtn

; zmc_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zmc_report:
            ldn     rb
            lbnz    zmc_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zmc_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zmc_had_failure: db     0

            end     start
