;
; zpropdiag_main.asm - ELF-DOS front end for the property diagnostics
;
; Usage: ZPROPDIAG
;
; Runs zpropdiag.asm's zpdiag_run against the property primitives
; (zprop.asm) and reports PASS/FAIL per check plus a summary line, all
; through the ELF-DOS kernel's console output calls.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zpdiag_run
            extrn   zp_results

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
            db      "check 0 (property 5: length 1, real address): ",0
            mov     rb, zp_results+0
            call    zp_report

            call    K_INMSG
            db      "check 1 (property 3: length 2, real address): ",0
            mov     rb, zp_results+1
            call    zp_report

            call    K_INMSG
            db      "check 2 (absent property: address 0, length 0): ",0
            mov     rb, zp_results+2
            call    zp_report

            call    K_INMSG
            db      "check 3 (get returns byte and word values): ",0
            mov     rb, zp_results+3
            call    zp_report

            call    K_INMSG
            db      "check 4 (absent property falls back to default): ",0
            mov     rb, zp_results+4
            call    zp_report

            call    K_INMSG
            db      "check 5 (property enumeration order): ",0
            mov     rb, zp_results+5
            call    zp_report

            call    K_INMSG
            db      "check 6 (empty enumeration, unlisted-property error): ",0
            mov     rb, zp_results+6
            call    zp_report

            mov     rf, zp_had_failure
            ldn     rf
            lbnz    zp_some_failed

            call    K_INMSG
            db      "All 7 checks passed.",13,10,0
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
