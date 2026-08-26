;
; zdiag_main.asm - ELF-DOS front end for the zmem/zstack diagnostics
;
; Usage: ZDIAG
;
; Runs zdiag.asm's zdiag_run against the resident dynamic-memory and
; eval-stack primitives and reports PASS/FAIL per check plus a summary
; line, all through the ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zdiag_run
            extrn   zd_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zdiag_run           ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zd_note_failure
            mov     rd, zd_had_failure
            ldi     0
            lbr     zd_store_flag
zd_note_failure:
            mov     rd, zd_had_failure
            ldi     1
zd_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (zmem write/read round trip): ",0
            mov     rb, zd_results+0
            call    zd_report

            call    K_INMSG
            db      "check 1 (zmem distinct-offset writes): ",0
            mov     rb, zd_results+1
            call    zd_report

            call    K_INMSG
            db      "check 2 (zmem write past dynamic end rejected): ",0
            mov     rb, zd_results+2
            call    zd_report

            call    K_INMSG
            db      "check 3 (zmem read past dynamic end rejected): ",0
            mov     rb, zd_results+3
            call    zd_report

            call    K_INMSG
            db      "check 4 (zstack push/pop LIFO order): ",0
            mov     rb, zd_results+4
            call    zd_report

            call    K_INMSG
            db      "check 5 (zstack pop-on-empty underflow): ",0
            mov     rb, zd_results+5
            call    zd_report

            call    K_INMSG
            db      "check 6 (zstack push-to-capacity overflow): ",0
            mov     rb, zd_results+6
            call    zd_report

            mov     rf, zd_had_failure
            ldn     rf
            lbnz    zd_some_failed

            call    K_INMSG
            db      "All 7 checks passed.",13,10,0
            ldi     0
            lbr     zd_exit

zd_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zd_exit:
            rtn

; zd_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zd_report:
            ldn     rb
            lbnz    zd_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zd_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zd_had_failure: db      0

            end     start
