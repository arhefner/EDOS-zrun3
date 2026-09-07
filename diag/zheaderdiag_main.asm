;
; zheaderdiag_main.asm - ELF-DOS front end for the V3 header parser
; diagnostics
;
; Usage: ZHEADERDIAG
;
; Runs zheaderdiag.asm's zhdiag_run against the V3 header parser
; (zheader.asm) and reports PASS/FAIL per check plus a summary line,
; all through the ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zhdiag_run
            extrn   zh_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zhdiag_run          ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zh_note_failure
            mov     rd, zh_had_failure
            ldi     0
            lbr     zh_store_flag
zh_note_failure:
            mov     rd, zh_had_failure
            ldi     1
zh_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (parse ZORK I's real header): ",0
            mov     rb, zh_results+0
            call    zh_report

            call    K_INMSG
            db      "check 1 (bad version rejected): ",0
            mov     rb, zh_results+1
            call    zh_report

            call    K_INMSG
            db      "check 2 (bad table ordering rejected): ",0
            mov     rb, zh_results+2
            call    zh_report

            mov     rf, zh_had_failure
            ldn     rf
            lbnz    zh_some_failed

            call    K_INMSG
            db      "All 3 checks passed.",13,10,0
            ldi     0
            lbr     zh_exit

zh_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zh_exit:
            rtn

; zh_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zh_report:
            ldn     rb
            lbnz    zh_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zh_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zh_had_failure: db      0

            end     start
