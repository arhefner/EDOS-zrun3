;
; zvardiag_main.asm - ELF-DOS front end for the call-frame/variable
; access diagnostics
;
; Usage: ZVARDIAG
;
; Runs zvardiag.asm's zvdiag_run against the call-frame stack and
; variable access primitives (zvar.asm) and reports PASS/FAIL per
; check plus a summary line, all through the ELF-DOS kernel's console
; output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zvdiag_run
            extrn   zvd_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zvdiag_run          ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zv_note_failure
            mov     rd, zv_had_failure
            ldi     0
            lbr     zv_store_flag
zv_note_failure:
            mov     rd, zv_had_failure
            ldi     1
zv_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (global write/read round trip): ",0
            mov     rb, zvd_results+0
            call    zv_report

            call    K_INMSG
            db      "check 1 (local access with no frame is rejected): ",0
            mov     rb, zvd_results+1
            call    zv_report

            call    K_INMSG
            db      "check 2 (local write/read, and a default local): ",0
            mov     rb, zvd_results+2
            call    zv_report

            call    K_INMSG
            db      "check 3 (local beyond local_count is rejected): ",0
            mov     rb, zvd_results+3
            call    zv_report

            call    K_INMSG
            db      "check 4 (variable 0 push/pop round trip): ",0
            mov     rb, zvd_results+4
            call    zv_report

            call    K_INMSG
            db      "check 5 (indirect peek/replace): ",0
            mov     rb, zvd_results+5
            call    zv_report

            call    K_INMSG
            db      "check 6 (frame pop returns/truncates correctly): ",0
            mov     rb, zvd_results+6
            call    zv_report

            call    K_INMSG
            db      "check 7 (popping an empty frame stack is rejected): ",0
            mov     rb, zvd_results+7
            call    zv_report

            call    K_INMSG
            db      "check 8 (more than 15 locals is rejected): ",0
            mov     rb, zvd_results+8
            call    zv_report

            mov     rf, zv_had_failure
            ldn     rf
            lbnz    zv_some_failed

            call    K_INMSG
            db      "All 9 checks passed.",13,10,0
            ldi     0
            lbr     zv_exit

zv_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zv_exit:
            rtn

; zv_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zv_report:
            ldn     rb
            lbnz    zv_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zv_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zv_had_failure: db      0

            end     start
