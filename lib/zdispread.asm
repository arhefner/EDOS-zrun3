;
; zdispread.asm - zdisp_read_line: the real ELF-DOS console
; implementation of zdispatch.asm's platform-level line-input hook
;
; A thin passthrough to lib/zterm.asm's own zterm_read_line, matching
; lib/zdispemit.asm's own precedent (and docs/ARCHITECTURE.md's
; platform-layer principle: the core, zdispatch.asm, never touches the
; ELF-DOS kernel or z_inputl directly, only this narrow interface) --
; a bare-metal diag build links in a different implementation instead
; (see diag/zdispatchdiag.asm's own canned-input version), without
; touching zdispatch.asm itself.
;

#include    include/opcodes.def

            extrn   zterm_read_line

; zdisp_read_line: RD = real host address of the text buffer, in the
; standard V3 format (byte 0 = max length, bytes 1.. filled in,
; already lowercased and NUL-terminated by zterm_read_line). Returns
; DF=1 if the user aborted the line with Ctrl-C.
            proc    zdisp_read_line
            call    zterm_read_line
            rtn
            endp
