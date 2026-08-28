;
; zdecodediag_main.asm - ELF-DOS front end for the instruction decoder
; diagnostics
;
; Usage: ZDECODEDIAG
;
; Runs zdecodediag.asm's zddiag_run against the V3 instruction decoder
; (zdecode.asm) and reports PASS/FAIL per check plus a summary line,
; all through the ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zddiag_run
            extrn   zdd_results

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            call    zddiag_run          ; DF=1 if any check failed --
                                        ; stash it before the K_INMSG
                                        ; calls below get a chance to
                                        ; clobber DF
            lbdf    zdd_note_failure
            mov     rd, zdd_had_failure
            ldi     0
            lbr     zdd_store_flag
zdd_note_failure:
            mov     rd, zdd_had_failure
            ldi     1
zdd_store_flag:
            str     rd

            call    K_INMSG
            db      "check 0 (long form, add, stores): ",0
            mov     rb, zdd_results+0
            call    zdd_report

            call    K_INMSG
            db      "check 1 (short form, jz, single-byte branch): ",0
            mov     rb, zdd_results+1
            call    zdd_report

            call    K_INMSG
            db      "check 2 (variable form, call, omitted operands): ",0
            mov     rb, zdd_results+2
            call    zdd_report

            call    K_INMSG
            db      "check 3 (short form, print, inline text): ",0
            mov     rb, zdd_results+3
            call    zdd_report

            call    K_INMSG
            db      "check 4 (long form, dec_chk, negative branch): ",0
            mov     rb, zdd_results+4
            call    zdd_report

            call    K_INMSG
            db      "check 5 (truncated instruction is rejected): ",0
            mov     rb, zdd_results+5
            call    zdd_report

            mov     rf, zdd_had_failure
            ldn     rf
            lbnz    zdd_some_failed

            call    K_INMSG
            db      "All 6 checks passed.",13,10,0
            ldi     0
            lbr     zdd_exit

zdd_some_failed:
            call    K_INMSG
            db      "One or more checks FAILED -- see above.",13,10,0
            ldi     1

zdd_exit:
            rtn

; zdd_report: RB = pointer to a result byte (0 = pass, nonzero = fail).
; Prints "PASS"/"FAIL" and a newline.
zdd_report:
            ldn     rb
            lbnz    zdd_report_fail
            call    K_INMSG
            db      "PASS",13,10,0
            rtn
zdd_report_fail:
            call    K_INMSG
            db      "FAIL",13,10,0
            rtn

zdd_had_failure: db      0

            end     start
