;
; zrun3_main.asm - the zrun3 ELF-DOS interpreter front end
;
; Usage: ZRUN3 <story-file>
;
; Loads and plays a V3 Z-machine story file. The status line (room
; name plus score/turns or time) is drawn via lib/zstatus.asm, using
; standard ANSI cursor-positioning escapes printed as ordinary text --
; zstatus_init is called once here, right after zload_story succeeds,
; to cache the terminal's COLUMNS/ROWS (read via lib/env.asm); each
; redraw after that is zds_sread's own job (called right before it
; reads a line), not this main loop's.
;
; The story filename comes from argv[1] -- ELF-DOS's own command line
; convention (RA = argv table, RC = argc at entry, per include/
; kernel_api.inc's own documented ABI); its own filesystem supports
; long filenames, so a story file's real name (spaces and all, e.g.
; "ZORK I") works directly, no 8.3 renaming needed.
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   bump_init
            extrn   zload_story
            extrn   zload_fail_stage
            extrn   zload_fail_avail
            extrn   zload_fail_req
            extrn   zstatus_init
            extrn   zdisp_step
            extrn   zdisp_quit
            extrn   zdisp_pc
            extrn   zdisp_pc_bank
            extrn   zde_fail_addr
            extrn   zcvalid
            extrn   zccount
            extrn   zcbase_lo
            extrn   zcfail_op
            extrn   ym_fmt_uint32
            extrn   zterm_print_string

            org     PROG_BASE

            db      'E','D','F'         ; ELF-DOS program magic
            db      1                   ; program major version
            db      0                   ; program minor version
            db      0                   ; reserved

;------------------------------------------------------------------
; Program entry point - PROG_BASE + $06
;------------------------------------------------------------------
start:
            mov     r8, zrun3_argc
            glo     rc
            str     r8                  ; zrun3_argc = argc (always
                                        ; small, one byte is plenty)
            mov     r8, zrun3_argv
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zrun3_argv = the argv table's
                                        ; own address -- both stashed
                                        ; immediately, before any call
                                        ; (including K_INMSG below) has
                                        ; a chance to clobber ra/rc

            mov     r8, zrun3_argc
            ldn     r8
            smi     2
            lbnf    zrun3_usage         ; argc < 2: no story file given

            mov     r8, zrun3_argv
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                  ; r9 = argv table address
            add16   r9, 2               ; r9 = &argv[1]
            lda     r9
            phi     ra
            ldn     r9
            plo     ra                  ; ra = argv[1] itself (a
                                        ; pointer to the path string)
            mov     r8, zrun3_path
            ghi     ra
            str     r8
            inc     r8
            glo     ra
            str     r8                  ; zrun3_path = argv[1]

            mov     rd, LOADER_ARGS
            lda     rd
            phi     r9
            ldn     rd
            plo     r9                  ; r9 = mem_base
            inc     rd
            lda     rd
            phi     ra
            ldn     rd
            plo     ra                  ; ra = mem_top (inclusive,
                                        ; matching bump_init's own RF
                                        ; convention exactly -- no
                                        ; adjustment needed)
            mov     rd, r9
            mov     rf, ra
            call    bump_init

            mov     r8, zrun3_path
            lda     r8
            phi     rf
            ldn     r8
            plo     rf                  ; rf = story path
            call    zload_story
            lbdf    zrun3_load_fail

            call    zstatus_init

zrun3_loop:
            call    zdisp_step
            lbdf    zrun3_error         ; a decode/opcode error stops
                                        ; the game cleanly rather than
                                        ; corrupting further state
            mov     r8, zdisp_quit
            ldn     r8
            lbz     zrun3_loop

            call    K_INMSG
            db      13,10,"[zrun3: story ended]",13,10,0
            ldi     0
            rtn

zrun3_error:
            call    K_INMSG
            db      13,10,"[zrun3: stopped -- decode or opcode error, pc=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zdisp_pc_bank
            ldn     r9                  ; d = bank (set last, right
                                        ; before the call -- mov clobbers
                                        ; d, so nothing but the call
                                        ; follows it)
            call    zrun3_hexbyte       ; writes 2 hex chars at rf,
                                        ; advancing it by 2
            ldi     ':'
            str     rf
            inc     rf
            mov     r9, zdisp_pc
            lda     r9                  ; d = pc high byte
            call    zrun3_hexbyte
            mov     r9, zdisp_pc        ; r9 re-fetched rather than
            inc     r9                  ; trusted to survive the call
            ldn     r9                  ; above (zrun3_hexbyte's own
                                        ; zrun3_hexnibble clobbers r9)
                                        ; -- d = pc low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf                  ; null-terminate
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", fail@",0
            mov     rf, zrun3_hexbuf
            mov     r9, zde_fail_addr
            lda     r9                  ; d = fail addr high byte
            call    zrun3_hexbyte
            mov     r9, zde_fail_addr   ; re-fetched, not trusted to
            inc     r9                  ; survive the call above (same
            ldn     r9                  ; reason as the pc print below
                                        ; it) -- d = fail addr low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", cvalid=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zcvalid
            inc     r9
            ldn     r9                  ; d = zcvalid's low byte (the
                                        ; word is really just 0/1)
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", ccount=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zccount
            lda     r9                  ; d = ccount high byte
            call    zrun3_hexbyte
            mov     r9, zccount
            inc     r9
            ldn     r9                  ; d = ccount low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", cbase=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zcbase_lo
            lda     r9                  ; d = cbase_lo high byte
            call    zrun3_hexbyte
            mov     r9, zcbase_lo
            inc     r9
            ldn     r9                  ; d = cbase_lo low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", op=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zcfail_op
            ldn     r9                  ; d = zcfail_op (1=seek, 2=read)
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      "]",13,10,0
            ldi     1
            rtn

; zrun3_hexbyte: d = byte value, rf = destination buffer -- writes 2
; ASCII hex chars and advances rf past them. Clobbers r7, r9, d.
zrun3_hexbyte:
            plo     r7                  ; r7.0 = byte
            glo     r7
            shr
            shr
            shr
            shr                         ; d = high nibble
            call    zrun3_hexnibble
            str     rf
            inc     rf
            glo     r7
            ani     $0f                 ; d = low nibble
            call    zrun3_hexnibble
            str     rf
            inc     rf
            rtn

; zrun3_hexnibble: d = nibble (0-15) -> d = its ASCII hex digit.
; Clobbers r9.
zrun3_hexnibble:
            plo     r9
            smi     10
            lbnf    zrun3_hn_digit      ; df=0 (borrow): nibble < 10
            glo     r9
            adi     'A'-10
            rtn
zrun3_hn_digit:
            glo     r9
            adi     '0'
            rtn

zrun3_load_fail:
            call    K_INMSG
            db      "zrun3: could not load story file (stage ",0
            mov     r9, zload_fail_stage
            ldn     r9
            plo     r8
            ldi     0
            phi     r8                  ; r8 = stage number (low word)
            phi     rd
            plo     rd                  ; rd = 0 (high word -- always
                                        ; fits in one byte, per
                                        ; ym_fmt_uint32's own RD:R8
                                        ; convention)
            mov     rf, zrun3_numbuf
            call    ym_fmt_uint32
            mov     rd, zrun3_numbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", avail=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zload_fail_avail
            lda     r9                  ; d = avail high byte
            call    zrun3_hexbyte
            mov     r9, zload_fail_avail
            inc     r9
            ldn     r9                  ; d = avail low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ", req=",0
            mov     rf, zrun3_hexbuf
            mov     r9, zload_fail_req
            lda     r9                  ; d = req high byte
            call    zrun3_hexbyte
            mov     r9, zload_fail_req
            inc     r9
            ldn     r9                  ; d = req low byte
            call    zrun3_hexbyte
            ldi     0
            str     rf
            mov     rd, zrun3_hexbuf
            call    zterm_print_string

            call    K_INMSG
            db      ")",13,10,0
            ldi     1
            rtn

zrun3_usage:
            call    K_INMSG
            db      "usage: ZRUN3 <story-file>",13,10,0
            ldi     1
            rtn

zrun3_argc:     db      0
zrun3_argv:     dw      0
zrun3_path:     dw      0
zrun3_numbuf:   ds      11      ; ym_fmt_uint32's own required minimum
zrun3_hexbuf:   ds      8       ; "BB:HHLL",0

            end     start
