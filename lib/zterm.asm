;
; zterm.asm - ELF-DOS terminal adapter (platform layer)
;
; Narrow wrappers around the ELF-DOS kernel's own console calls, so
; the eventual VM core only ever depends on this interface, never on
; K_TYPE/K_MSG/z_inputl directly (see docs/ARCHITECTURE.md's platform
; layer). zterm_lowercase is the one piece here with no kernel
; dependency, so it's the only piece a bare emulator (no kernel
; loaded) can verify -- print_char/print_string/read_line's own
; kernel-call plumbing needs the real kernel, hardware or a full boot,
; the same caveat zcache.asm's file I/O carries.
;
; zterm_read_line is built on lib/zinputl.asm's z_inputl, a local
; character-at-a-time line reader (K_READ plus its own echo/backspace
; handling) written to replace the kernel's own former K_INPUTL, which
; was removed upstream (see kernel_api.inc's own note on the removal --
; superseded project-wide by lib/lineedit.asm's read_line_ex, but this
; project's own narrow needs are served by the smaller z_inputl
; instead). Unlike K_INPUTL, z_inputl has no input-redirection
; awareness; its DF instead reports whether the user aborted the line
; with Ctrl-C.
;
; Register budget matches the rest of this project: only R7-RD and
; RF, no R1, no RE. Nothing here assumes any register survives a
; kernel call, or a call to z_inputl itself (an ordinary subroutine,
; not a kernel call, but one this file doesn't control the internals
; of and that makes several kernel calls of its own).
;

#include    include/opcodes.def
#include    include/kernel_api.inc

            extrn   zterm_lowercase
            extrn   zrl_buf_addr
            extrn   zrl_had_abort
            extrn   z_inputl

; zterm_print_char: D = character (set by the caller immediately
; before the call).
            proc    zterm_print_char
            call    K_TYPE
            rtn
            endp

; zterm_print_string: RD = address of a null-terminated ASCII string.
            proc    zterm_print_string
            mov     rf, rd
            call    K_MSG
            rtn
            endp

; zterm_lowercase: RD = address of a null-terminated ASCII string.
; Lowercases it in place; leaves everything else untouched. The one
; routine in this file with no kernel dependency, so it's the one
; diag/ztermdiag.asm actually exercises under an emulator.
            proc    zterm_lowercase
            mov     rf, rd
ztl_loop:
            ldn     rf
            lbz     ztl_done
            smi     'A'
            lbnf    ztl_next            ; c < 'A': leave as-is
            ldn     rf
            smi     'Z'+1
            lbdf    ztl_next            ; c > 'Z': leave as-is
            ldn     rf
            adi     32                  ; 'a' - 'A': lowercase it
            str     rf
ztl_next:
            inc     rf
            lbr     ztl_loop
ztl_done:
            clc
            rtn
            endp

; zterm_read_line: RD = text buffer address in the standard V3 format
; (byte 0 = max length, bytes 1.. filled in, lowercase, NUL-
; terminated). Returns DF=1 if the user aborted the line with Ctrl-C
; (z_inputl's own signal for that -- the buffer is still NUL-
; terminated in that case, just short/empty rather than a real line).
            proc    zterm_read_line
            mov     r8, rd              ; r8 = text buffer address
            ldn     r8                  ; d = max length
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:max_length
            inc     r8                  ; r8 = buffer+1 (where z_inputl
                                        ; writes)
            mov     rf, zrl_buf_addr
            ghi     r8
            str     rf
            inc     rf
            glo     r8
            str     rf                  ; zrl_buf_addr = buffer+1 --
                                        ; kept in memory, not a
                                        ; register, since nothing is
                                        ; safe to assume survives the
                                        ; kernel calls below

            mov     rf, r8
            call    z_inputl            ; rf = filled buffer, df=1 if
                                        ; the user aborted with Ctrl-C
            lbdf    zrl_was_aborted
            mov     rf, zrl_had_abort
            ldi     0
            lbr     zrl_have_flag
zrl_was_aborted:
            mov     rf, zrl_had_abort
            ldi     1
zrl_have_flag:
            str     rf                  ; zrl_had_abort = the DF
                                        ; z_inputl gave us

            ldi     10                  ; the BIOS's own f_inputl only
                                        ; echoes a bare CR on Enter, no
                                        ; LF (confirmed against
                                        ; Elfos-mbios/mbios.asm's
                                        ; inputl/cr), so the cursor
                                        ; stays on the just-typed line
                                        ; unless we finish the move to
                                        ; a fresh one ourselves
            call    K_TYPE

            mov     rf, zrl_buf_addr
            lda     rf
            phi     rd
            ldn     rf
            plo     rd                  ; rd = buffer+1 (reloaded --
                                        ; see the comment above)
            call    zterm_lowercase

            mov     rf, zrl_had_abort
            ldn     rf
            lbz     zrl_ok
            stc
            rtn
zrl_ok:
            clc
            rtn
            endp

            proc    _zterm_data
zrl_buf_addr:   dw      0
zrl_had_abort:  db      0
                public  zrl_buf_addr
                public  zrl_had_abort
            endp
