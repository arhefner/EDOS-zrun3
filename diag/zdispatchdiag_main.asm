;
; zdispatchdiag_main.asm - ELF-DOS front end for the opcode execution
; engine diagnostics
;
; Usage: ZDISPATCHDIAG
;
; Runs zdispatchdiag.asm's zddiag_run against the V3 opcode execution
; engine (zdispatch.asm) and reports PASS/FAIL per check plus a
; summary line, all through the ELF-DOS kernel's console output calls.
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
            db      "check 0 (call + add + ret): ",0
            mov     rb, zdd_results+0
            call    zd_report

            call    K_INMSG
            db      "check 1 (je taken and not taken): ",0
            mov     rb, zdd_results+1
            call    zd_report

            call    K_INMSG
            db      "check 2 (sub, jz, store, jump, quit): ",0
            mov     rb, zdd_results+2
            call    zd_report

            call    K_INMSG
            db      "check 3 (print, new_line, call+print_ret): ",0
            mov     rb, zdd_results+3
            call    zd_report

            call    K_INMSG
            db      "check 4 (attributes, object-tree queries): ",0
            mov     rb, zdd_results+4
            call    zd_report

            call    K_INMSG
            db      "check 5 (properties, insert_obj, remove_obj): ",0
            mov     rb, zdd_results+5
            call    zd_report

            call    K_INMSG
            db      "check 6 (arithmetic, comparison): ",0
            mov     rb, zdd_results+6
            call    zd_report

            call    K_INMSG
            db      "check 7 (memory access, put_prop): ",0
            mov     rb, zdd_results+7
            call    zd_report

            call    K_INMSG
            db      "check 8 (print family, stack opcodes): ",0
            mov     rb, zdd_results+8
            call    zd_report

            call    K_INMSG
            db      "check 9 (random, sread): ",0
            mov     rb, zdd_results+9
            call    zd_report

            call    K_INMSG
            db      "check 10 (output_stream, input_stream): ",0
            mov     rb, zdd_results+10
            call    zd_report

            call    K_INMSG
            db      "check 11 (save, restore, restart): ",0
            mov     rb, zdd_results+11
            call    zd_report

            call    K_INMSG
            db      "check 12 (mul, div, mod): ",0
            mov     rb, zdd_results+12
            call    zd_report

            call    K_INMSG
            db      "check 13 (print_paddr via zmread's real cache path): ",0
            mov     rb, zdd_results+13
            call    zd_report

            call    K_INMSG
            db      "check 14 (zwide_add_signed bank carry/borrow): ",0
            mov     rb, zdd_results+14
            call    zd_report

            mov     rf, zd_had_failure
            ldn     rf
            lbnz    zd_some_failed

            call    K_INMSG
            db      "All 15 checks passed.",13,10,0
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
