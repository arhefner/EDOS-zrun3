;
; zterm.asm - ELF-DOS terminal adapter (platform layer)
;
; Narrow wrappers around the ELF-DOS kernel's own console calls, so
; the eventual VM core only ever depends on this interface, never on
; K_TYPE/K_MSG/K_INPUTL directly (see docs/ARCHITECTURE.md's platform
; layer). zterm_lowercase is the one piece here with no kernel
; dependency, so it's the only piece a bare emulator (no kernel
; loaded) can verify -- print_char/print_string/read_line's own
; kernel-call plumbing needs the real kernel, hardware or a full boot,
; the same caveat zcache.asm's file I/O carries.
;
; Register budget matches the rest of this project: only R7-RD and
; RF, no R1, no RE. Nothing here assumes any register survives a
; kernel call -- kernel/redir.asm's own K_INPUTL dispatcher comment is
; explicit that nothing is safe to assume preserved across it.
;

#include    include/opcodes.def
#include    include/kernel_api.inc

            extrn   zterm_lowercase
            extrn   zrl_buf_addr
            extrn   zrl_had_eof

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
; terminated). Returns DF=1 if input redirection is exhausted (see
; K_INPUTL's own doc comment in kernel_api.inc) -- never true for a
; live keyboard, so most callers can ignore it.
            proc    zterm_read_line
            mov     r8, rd              ; r8 = text buffer address
            ldn     r8                  ; d = max length
            plo     rc
            ldi     0
            phi     rc                  ; rc = 0:max_length
            inc     r8                  ; r8 = buffer+1 (where K_INPUTL
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
            call    K_INPUTL            ; rf = filled buffer, df=1 if
                                        ; redirected input is exhausted
            lbdf    zrl_was_redirected
            mov     rf, zrl_had_eof
            ldi     0
            lbr     zrl_have_flag
zrl_was_redirected:
            mov     rf, zrl_had_eof
            ldi     1
zrl_have_flag:
            str     rf                  ; zrl_had_eof = the DF
                                        ; K_INPUTL gave us

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

            mov     rf, zrl_had_eof
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
zrl_had_eof:    db      0
                public  zrl_buf_addr
                public  zrl_had_eof
            endp
