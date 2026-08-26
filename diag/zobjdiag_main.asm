;
; zobjdiag_main.asm - ELF-DOS front end for the object/attribute
; diagnostics
;
; Usage: ZOBJDIAG
;
; Runs zobjdiag.asm's zodiag_run against the object tree and attribute
; primitives (zobj.asm) and reports PASS/FAIL per check plus a summary
; line, all through the ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zodiag_run
            extrn   zo_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zodiag_run          ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zo_note_failure
            mov     rd, zo_had_failure
            ldi     0
            lbr     zo_store_flag
zo_note_failure:
            mov     rd, zo_had_failure
            ldi     1
zo_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (initial tree shape): ",0
            mov     rb, zo_results+0
            call    zo_report

            call    K_INMSG
            db      "check 1 (attribute set/clear round trip): ",0
            mov     rb, zo_results+1
            call    zo_report

            call    K_INMSG
            db      "check 2 (two attributes don't interfere): ",0
            mov     rb, zo_results+2
            call    zo_report

            call    K_INMSG
            db      "check 3 (remove promotes sibling to child): ",0
            mov     rb, zo_results+3
            call    zo_report

            call    K_INMSG
            db      "check 4 (insert attaches as new child): ",0
            mov     rb, zo_results+4
            call    zo_report

            call    K_INMSG
            db      "check 5 (short name address/length): ",0
            mov     rb, zo_results+5
            call    zo_report

            mov     rf, zo_had_failure
            ldn     rf
            lbnz    zo_some_failed

            call    K_INMSG
            db      "All 6 checks passed.",13,10,0
            ldi     0
            lbr     zo_exit

zo_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zo_exit:
            rtn

; zo_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zo_report:
            ldn     rb
            lbnz    zo_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zo_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zo_had_failure: db      0

            end     start
