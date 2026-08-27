;
; ztermdiag_main.asm - interactive ELF-DOS demo for the terminal
; adapter (zterm.asm)
;
; Usage: ZTERMDIAG
;
; Unlike the other diag/*_main.asm programs, this isn't an automated
; PASS/FAIL check list: print_char/print_string/read_line's own
; kernel-call plumbing has no bare-metal equivalent to verify against
; (see zterm.asm's own header comment), so this exercises all three
; and asks the person running it to judge the result by eye --
; specifically, that the typed line comes back lowercased.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zterm_print_char
            extrn   zterm_print_string
            extrn   zterm_read_line

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            mov     rd, zt_intro
            call    zterm_print_string

            mov     rd, zt_char_label
            call    zterm_print_string
            ldi     'X'
            call    zterm_print_char
            mov     rd, zt_newline
            call    zterm_print_string

            mov     rd, zt_prompt
            call    zterm_print_string
            mov     rd, zt_line_buf
            call    zterm_read_line
            lbdf    zt_aborted

            mov     rd, zt_echo_label
            call    zterm_print_string
            mov     rd, zt_line_buf+1
            call    zterm_print_string
            mov     rd, zt_newline
            call    zterm_print_string
            ldi     0
            rtn

zt_aborted:
            mov     rd, zt_abort_msg
            call    zterm_print_string
            ldi     1
            rtn

zt_intro:       db      "Terminal adapter test.",13,10,0
zt_char_label:  db      "print_char('X'): ",0
zt_newline:     db      13,10,0
zt_prompt:      db      "Type something in ANY case, "
                db      "press enter: ",0
zt_echo_label:  db      "read back (should be all lowercase): ",0
zt_abort_msg:   db      "line aborted with Ctrl-C -- ",
                db      "no line to echo.",13,10,0
zt_line_buf:    db      63
                ds      63

            end     start
