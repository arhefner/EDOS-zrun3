;
; zparsediag_main.asm - ELF-DOS front end for the tokenizer
; diagnostics
;
; Usage: ZPARSEDIAG
;
; Runs zparsediag.asm's zpdiag_run against the tokenizer (zparse.asm)
; and reports PASS/FAIL per check plus a summary line, all through the
; ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zpdiag_run
            extrn   zt_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zpdiag_run          ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zp_note_failure
            mov     rd, zp_had_failure
            ldi     0
            lbr     zp_store_flag
zp_note_failure:
            mov     rd, zp_had_failure
            ldi     1
zp_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (4 words found): ",0
            mov     rb, zt_results+0
            call    zp_report

            call    K_INMSG
            db      "check 1 ('take': unlisted, length 4, position 2): ",0
            mov     rb, zt_results+1
            call    zp_report

            call    K_INMSG
            db      "check 2 ('cat': found, length 3, position 7): ",0
            mov     rb, zt_results+2
            call    zp_report

            call    K_INMSG
            db      "check 3 (',': separator as its own token): ",0
            mov     rb, zt_results+3
            call    zp_report

            call    K_INMSG
            db      "check 4 ('run': found, length 3, position 12): ",0
            mov     rb, zt_results+4
            call    zp_report

            mov     rf, zp_had_failure
            ldn     rf
            lbnz    zp_some_failed

            call    K_INMSG
            db      "All 5 checks passed.",13,10,0
            ldi     0
            lbr     zp_exit

zp_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zp_exit:
            rtn

; zp_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zp_report:
            ldn     rb
            lbnz    zp_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zp_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zp_had_failure: db      0

            end     start
