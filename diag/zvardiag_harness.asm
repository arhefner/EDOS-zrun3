; zvardiag_harness.asm - bare-metal entry point for running
; zvdiag_run under an emulator with no ELF-DOS kernel loaded. See
; diag/zdiag_harness.asm for the same pattern applied to zdiag_run;
; not built by the project Makefile.

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zvdiag_run

            org     PROG_BASE

start:      mov     r2, $7fff
            mov     r6, main
            lbr     f_initcall

main:
            call    zvdiag_run
            brkpt
spin:       lbr     spin

            end     start
