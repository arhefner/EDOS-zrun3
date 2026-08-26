;
; zdiag_harness.asm - bare-metal entry point for running zdiag_run under
; an emulator with no ELF-DOS kernel loaded (see Run02/test.asm for the
; f_initcall/SCRT bootstrap this follows). Not an ELF-DOS program --
; this is throwaway scaffolding for exercising zdiag_run's logic in
; run02 directly; it is not built by the project Makefile.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zdiag_run

            org     PROG_BASE

start:      mov     r2, $7fff
            mov     r6, main
            lbr     f_initcall

main:
            call    zdiag_run
            brkpt                       ; run02: `t+79` then `@start` stops
                                        ; here so results can be inspected
spin:       lbr     spin

            end     start
