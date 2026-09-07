;
; zdispsave.asm - zdisp_save_game/zdisp_restore_game: the real
; ELF-DOS file-backed implementation of zdispatch.asm's platform-level
; save/restore hooks
;
; Dumps/restores a simple, self-describing raw state blob to/from a
; fixed file name (SAVE.DAT) -- not Quetzal-format, not compatible
; with other Z-machine interpreters, matching host/dispatch.h's own
; vm_save_fn/vm_restore_fn design note that the reference model
; doesn't serialize anything itself, it just hands the platform a live
; pointer to the VM's own state and dynamic-memory bytes and leaves
; the actual format entirely up to the platform. Layout (all
; multi-byte fields big-endian, matching this project's own convention
; throughout):
;   pc (2), pc_bank (1) -- the bank/high-word half of a wide V3 pc, for
;   a story file over 64K,
;   globals_base (2),
;   eval_stack_length (2) + that many bytes (from *zsbase),
;   frame_stack_length (2) + that many bytes (from *zv_frame_base --
;   this is a raw byte count, not frame-count*FRAME_SIZE, so it needed
;   no change when FRAME_SIZE itself grew to hold a return address's
;   own bank),
;   rand_state (4, raw),
;   dynamic_memory_length (2, == zmend) + that many bytes (from
;   *zmbase)
;
; Like every other platform hook here, a bare-metal diag build links
; in a different implementation instead of this one (see
; diag/zdispatchdiag.asm's own in-memory-buffer test double), matching
; lib/zdispemit.asm/lib/zdispread.asm's own precedent -- the core
; (zdispatch.asm) never touches K_FILE_* directly, only
; zdisp_save_game/zdisp_restore_game.
;
; If zdisp_restore_game fails partway through (a truncated or
; corrupted save file), whatever fields it already overwrote before
; the failure stay overwritten -- restore is not atomic. This matches
; host/dispatch.h's own vm_restore_fn contract, which makes no
; atomicity guarantee either (restoring is a single opaque callback
; there); a save file produced by this module's own zdisp_save_game is
; always complete and well-formed under normal operation, so this is
; an accepted, not a hidden, limitation.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   zdisp_pc
            extrn   zdisp_pc_bank
            extrn   zv_globals_base
            extrn   zsbase
            extrn   zsptr
            extrn   zv_frame_base
            extrn   zv_frame_ptr
            extrn   zrand_state
            extrn   zmbase
            extrn   zmend

            extrn   zds_path
            extrn   zds_fcb
            extrn   zds_iobuf
            extrn   zds_scratch

; zdisp_save_game: no arguments. Returns DF=1 on any failure (file
; open/write/close error) -- best-effort closes the file first if a
; write failed partway through, so a failed save doesn't also leak an
; open FCB.
            proc    zdisp_save_game
            mov     rf, zds_path
            mov     rd, zds_fcb
            mov     ra, zds_iobuf
            ldi     1                   ; mode 1: create/overwrite,
                                        ; always truncates fresh
            call    K_FILE_OPEN
            lbdf    zsg_fail_noclose

            mov     rf, zdisp_pc        ; pc (scalar, 2 bytes)
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, zdisp_pc_bank   ; pc's own bank (scalar, 1
                                        ; byte) -- a V3 story file over
                                        ; 64K can have pc pointing
                                        ; beyond the first 64K at save
                                        ; time
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     1
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, zv_globals_base ; globals_base (scalar, 2 bytes)
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

; eval stack: length (zsptr - zsbase), then that many content bytes
; starting at *zsbase
            mov     r8, zsptr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = *zsptr
            mov     r8, zsbase
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = *zsbase
            mov     r7, r9
            sub16   r7, ra              ; r7 = eval stack length

            mov     rf, zds_scratch
            ghi     r7
            str     rf
            inc     rf
            glo     r7
            str     rf
            mov     rf, zds_scratch
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, ra              ; rf = *zsbase (content start)
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

; frame stack: length (frame_ptr - frame_base), then content
            mov     r8, zv_frame_ptr
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zv_frame_base
            lda     r8
            phi     ra
            ldn     r8
            plo     ra
            mov     r7, r9
            sub16   r7, ra

            mov     rf, zds_scratch
            ghi     r7
            str     rf
            inc     rf
            glo     r7
            str     rf
            mov     rf, zds_scratch
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, ra
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, zrand_state     ; rand_state (raw, 4 bytes)
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     4
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rf, zmend           ; dynamic memory length
                                        ; (scalar, 2 bytes)
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     r8, zmend
            lda     r8
            phi     r7
            ldn     r8
            plo     r7                  ; r7 = *zmend (length)
            mov     r8, zmbase
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = *zmbase (content start)
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_WRITE
            lbdf    zsg_fail

            mov     rd, zds_fcb
            call    K_FILE_CLOSE        ; DELIBERATE: the close's own DF
                                        ; IS this routine's result -- a
                                        ; save whose close failed did not
                                        ; fully persist. Unlike K_MSG/
                                        ; K_TYPE (whose DF is undefined
                                        ; and must never be passed up --
                                        ; see lib/zdispemit.asm),
                                        ; K_FILE_CLOSE documents DF = 0/1
                                        ; in kernel_api.inc.
            rtn

zsg_fail:
            mov     rd, zds_fcb
            call    K_FILE_CLOSE        ; best-effort; DF ignored
            stc
            rtn

zsg_fail_noclose:
            stc
            rtn
            endp

; zdisp_restore_game: no arguments. Returns DF=1 on any failure (see
; this file's own header for why a failure partway through is not
; atomic).
            proc    zdisp_restore_game
            mov     rf, zds_path
            mov     rd, zds_fcb
            mov     ra, zds_iobuf
            ldi     0                   ; mode 0: read
            call    K_FILE_OPEN
            lbdf    zrg_fail_noclose

            mov     rf, zdisp_pc
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     rf, zdisp_pc_bank
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     1
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     rf, zv_globals_base
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

; eval stack: length, then content -- restore zsptr = *zsbase + length
            mov     rf, zds_scratch
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     r8, zds_scratch
            lda     r8
            phi     r7
            ldn     r8
            plo     r7                  ; r7 = length

            mov     r8, zsbase
            lda     r8
            phi     ra
            ldn     r8
            plo     ra                  ; ra = *zsbase

            mov     r9, ra
            add16   r9, r7              ; r9 = *zsbase + length = the
                                        ; new zsptr -- computed NOW,
                                        ; before K_FILE_READ, whose
                                        ; clobber footprint isn't
                                        ; documented beyond RD/RF/RC
                                        ; and can't be trusted to leave
                                        ; R7 alone
            mov     r8, zds_scratch
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8                  ; zds_scratch = new zsptr,
                                        ; stashed in memory across the
                                        ; call below

            mov     rf, ra
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     r8, zds_scratch
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = new zsptr, reloaded
                                        ; fresh
            mov     r8, zsptr
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

; frame stack: length, then content -- restore frame_ptr =
; *zv_frame_base + length
            mov     rf, zds_scratch
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     r8, zds_scratch
            lda     r8
            phi     r7
            ldn     r8
            plo     r7

            mov     r8, zv_frame_base
            lda     r8
            phi     ra
            ldn     r8
            plo     ra

            mov     r9, ra
            add16   r9, r7              ; new frame_ptr, computed
                                        ; before K_FILE_READ (see the
                                        ; eval-stack section's own note
                                        ; above for why)
            mov     r8, zds_scratch
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     rf, ra
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     r8, zds_scratch
            lda     r8
            phi     r9
            ldn     r8
            plo     r9
            mov     r8, zv_frame_ptr
            ghi     r9
            str     r8
            inc     r8
            glo     r9
            str     r8

            mov     rf, zrand_state
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     4
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

; dynamic memory: length (also the new zmend), then content
            mov     rf, zds_scratch
            mov     rd, zds_fcb
            ldi     0
            phi     rc
            ldi     2
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     r8, zds_scratch
            lda     r8
            phi     r7
            ldn     r8
            plo     r7                  ; r7 = length

            mov     r8, zmend
            ghi     r7
            str     r8
            inc     r8
            glo     r7
            str     r8                  ; zmend = length

            mov     r8, zmbase
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = *zmbase (content start)
            mov     rd, zds_fcb
            ghi     r7
            phi     rc
            glo     r7
            plo     rc
            call    K_FILE_READ
            lbdf    zrg_fail

            mov     rd, zds_fcb
            call    K_FILE_CLOSE        ; DELIBERATE, same as save's own
                                        ; close above: K_FILE_CLOSE's DF
                                        ; is documented and is the result.
            rtn

zrg_fail:
            mov     rd, zds_fcb
            call    K_FILE_CLOSE        ; best-effort; DF ignored
            stc
            rtn

zrg_fail_noclose:
            stc
            rtn
            endp

            proc    _zdispsave_data
zds_path:       db      "SAVE.DAT",0
zds_fcb:        ds      FCB_LEN
zds_iobuf:      ds      FCB_IOBUF_LEN
zds_scratch:    ds      2
                public  zds_path
                public  zds_fcb
                public  zds_iobuf
                public  zds_scratch
            endp
