;
; zdispemit.asm - zdisp_emit_string: the real ELF-DOS console
; implementation of zdispatch.asm's platform-level string-output hook
;
; A thin passthrough to K_MSG, matching docs/ARCHITECTURE.md's
; platform-layer principle: the core (zdispatch.asm) never calls an
; ELF-DOS kernel entry point directly, only this narrow interface --
; so a bare-metal diag build can link in a different implementation
; (see diag/zdispatchdiag.asm's own capture-buffer version) without
; touching zdispatch.asm itself. K_MSG requires the full ELF-DOS
; kernel (not just the F800 BIOS), matching how every other kernel-
; touching diag_main.asm in this project is an ELF-DOS front end, not
; a bare-metal harness -- an eventual interpreter program links this
; module in; a bare-metal diag build does not.
;

#include    include/opcodes.def
#include    include/kernel_api.inc

; zdisp_emit_string: RF = NUL-terminated string (set immediately
; before the call).
            proc    zdisp_emit_string
            call    K_MSG
            rtn
            endp
