;
; zstatus.asm - V3 status line (score/turns or time, plus the current
; room's short name), drawn via standard ANSI cursor-positioning
; escape sequences printed as ordinary text through lib/zterm.asm --
; no new kernel/BIOS primitive needed, since a real terminal already
; interprets these.
;
; zstatus_init reads the COLUMNS/ROWS environment variables once (via
; lib/env.asm's env_getenv, which does real file I/O -- reading them
; every redraw would mean a disk read after every player command) and
; caches them; a mid-game terminal resize won't be picked up until the
; next launch, an accepted trade-off. f_atoi (BIOS+5dh) converts the
; decimal string env_getenv returns into a binary value -- this
; project has no prior use of f_atoi to confirm its exact convention
; against, so this follows the standard Elf/OS BIOS documentation
; (RF = input string in, RD = binary value out, RF = updated past the
; consumed digits) rather than something verified here; hardware
; testing will confirm or correct it. Either variable missing, or a
; parse producing 0, falls back to a conservative default (80 columns,
; 24 rows) rather than drawing something nonsensical.
;
; zstatus_draw redraws the status line at the top of the screen
; without disturbing where the game's own text is currently being
; printed (save/restore cursor around the whole thing). The room name
; comes from decoding the object in global variable 0 (Z-machine
; variable 16) exactly the way print_obj already does (zvar_read +
; zobj_short_name + zdec_decode); score/turns vs. time mode is chosen
; from the header's own Flags1 bit 1 (bit set = time game), read
; directly via zmread since it's always resident (guest address 1).
; The score/turns (or time) section is right-aligned using the
; cached COLUMNS value (a fixed, generous width reserved for it, not
; exact string-length tracking -- an overlong room name could crowd
; it on a narrow terminal, the same rough edge most simple Z-machine
; interpreters accept here).
;

#include    include/opcodes.def
#include    include/bios.inc
#include    include/kernel_api.inc

            extrn   env_getenv
            extrn   zterm_print_string
            extrn   zterm_print_char
            extrn   zvar_read
            extrn   zobj_short_name
            extrn   zdec_decode
            extrn   zmread
            extrn   ym_fmt_uint32

            extrn   zstatus_columns
            extrn   zstatus_rows
            extrn   zstatus_had_error
            extrn   zstatus_buf
            extrn   zstatus_numbuf
            extrn   zstatus_minutes
            extrn   zstatus_env_columns
            extrn   zstatus_env_rows
            extrn   zstatus_esc_save
            extrn   zstatus_esc_restore
            extrn   zstatus_esc_home
            extrn   zstatus_esc_reverse
            extrn   zstatus_esc_normal
            extrn   zstatus_esc_clear
            extrn   zstatus_esc_col_prefix
            extrn   zstatus_label_score
            extrn   zstatus_label_moves
            extrn   zstatus_label_time
            extrn   zstatus_print_signed

ZSTATUS_RESERVED:       equ     28      ; generous fixed width for
                                        ; "Score: -32768  Moves: 65535"
                                        ; (or the time equivalent),
                                        ; right-aligned within it
ZSTATUS_MIN_COLUMN:     equ     40      ; never try to right-align
                                        ; past this, however narrow
                                        ; COLUMNS turns out to be

; zstatus_init: no arguments. Reads and caches COLUMNS/ROWS. Always
; succeeds (falls back to defaults on any lookup/parse failure).
            proc    zstatus_init
            mov     rf, zstatus_env_columns
            call    env_getenv
            glo     rf
            lbnz    zsi_have_columns
            ghi     rf
            lbnz    zsi_have_columns
            lbr     zsi_columns_default     ; not found: rf == 0

zsi_have_columns:
            mov     rd, rf
            call    f_atoi                  ; rd = parsed value
            glo     rd
            lbnz    zsi_store_columns
            ghi     rd
            lbnz    zsi_store_columns
zsi_columns_default:
            mov     rd, 80
zsi_store_columns:
            mov     r8, zstatus_columns
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8

            mov     rf, zstatus_env_rows
            call    env_getenv
            glo     rf
            lbnz    zsi_have_rows
            ghi     rf
            lbnz    zsi_have_rows
            lbr     zsi_rows_default
zsi_have_rows:
            mov     rd, rf
            call    f_atoi
            glo     rd
            lbnz    zsi_store_rows
            ghi     rd
            lbnz    zsi_store_rows
zsi_rows_default:
            mov     rd, 24
zsi_store_rows:
            mov     r8, zstatus_rows
            ghi     rd
            str     r8
            inc     r8
            glo     rd
            str     r8

            rtn
            endp

; zstatus_draw: no arguments. Redraws the status line. DF=1 if the
; room's own short name fails to decode (the rest is still drawn --
; cursor is still restored -- just without a location name); score/
; turns/time are simple global reads and never fail.
            proc    zstatus_draw
            mov     rd, zstatus_esc_save
            call    zterm_print_string
            mov     rd, zstatus_esc_home
            call    zterm_print_string
            mov     rd, zstatus_esc_reverse
            call    zterm_print_string
            mov     rd, zstatus_esc_clear
            call    zterm_print_string

            ldi     ' '
            call    zterm_print_char

; ---- room name: global variable 0 (Z-machine variable 16) ----
            ldi     16
            call    zvar_read               ; rf = object number
            lbdf    zsd_room_fail
            mov     rd, rf
            call    zobj_short_name         ; rf = real text addr,
                                            ; rc = length
            mov     rd, rf
            mov     rf, zstatus_buf
            call    zdec_decode
            lbdf    zsd_room_fail

            mov     rd, zstatus_buf
            call    zterm_print_string
            lbr     zsd_room_done
zsd_room_fail:
            stc                             ; remember the failure --
            mov     r8, zstatus_had_error   ; still draw the rest of
            ldi     1                       ; the line rather than
            str     r8                      ; bailing out partway
            lbr     zsd_score
zsd_room_done:
            mov     r8, zstatus_had_error
            ldi     0
            str     r8

zsd_score:
; ---- move to the reserved section's own start column ----
            mov     r8, zstatus_columns
            lda     r8
            phi     r9
            ldn     r8
            plo     r9                      ; r9 = columns
            sub16   r9, ZSTATUS_RESERVED    ; r9 = columns - reserved
            lbnf    zsd_use_min             ; underflowed: too narrow
            ghi     r9
            lbnz    zsd_have_column         ; > 255: definitely wide
                                            ; enough, keep it
            glo     r9
            smi     ZSTATUS_MIN_COLUMN
            lbdf    zsd_have_column         ; >= minimum: keep it
zsd_use_min:
            mov     r9, ZSTATUS_MIN_COLUMN
zsd_have_column:
            mov     r8, r9                  ; r8 = column value (low
                                            ; word)
            ldi     0
            phi     rd
            plo     rd                      ; rd = 0 (high word)
            mov     rf, zstatus_numbuf
            call    ym_fmt_uint32           ; formats r8 (rd:r8) into
                                            ; zstatus_numbuf

            mov     rd, zstatus_esc_col_prefix
            call    zterm_print_string      ; "\x1b["
            mov     rd, zstatus_numbuf
            call    zterm_print_string
            ldi     'G'
            call    zterm_print_char

; ---- score/turns or time, from the header's own Flags1 bit 1 ----
            mov     rd, 1
            call    zmread                  ; d = flags1 (guest addr 1
                                            ; is always resident --
                                            ; part of the header, well
                                            ; below dynamic_end)
            ani     2
            lbnz    zsd_time_mode

            mov     rd, zstatus_label_score
            call    zterm_print_string      ; label printed FIRST --
                                            ; zterm_print_string's own
                                            ; call chain (K_MSG) has no
                                            ; documented clobber
                                            ; footprint, so zvar_read's
                                            ; result can't be trusted
                                            ; to survive it; reordering
                                            ; so the read feeds
                                            ; zstatus_print_signed with
                                            ; no call in between avoids
                                            ; needing to stash it at all
            ldi     17
            call    zvar_read               ; rf = score (signed)
            call    zstatus_print_signed

            mov     rd, zstatus_label_moves
            call    zterm_print_string
            ldi     18
            call    zvar_read               ; rf = moves
            call    zstatus_print_signed
            lbr     zsd_done

zsd_time_mode:
            mov     rd, zstatus_label_time
            call    zterm_print_string
            ldi     17
            call    zvar_read               ; rf = hours
            call    zstatus_print_signed

            ldi     ':'
            call    zterm_print_char

            ldi     18
            call    zvar_read               ; rf = minutes
            mov     r8, zstatus_minutes     ; stash it: the '0' pad below
            ghi     rf                      ; goes out through K_TYPE,
            str     r8                      ; which no register survives
            inc     r8
            glo     rf
            str     r8

; zero-pad the minutes: the Z-machine's time status line is HH:MM, so a
; minute under 10 needs a leading '0' -- without it MOONMIST's own clock
; read "Time: 19:0" rather than "19:00" for the first ten minutes of
; every hour. Only 0-9 is padded; anything negative (which shouldn't
; happen) is left to print_signed's own '-' handling.
            ghi     rf
            lbnz    zsd_min_wide            ; >= 256, certainly not < 10
            glo     rf
            smi     10
            lbdf    zsd_min_wide            ; DF=1 (no borrow): >= 10
            ldi     '0'
            call    zterm_print_char
zsd_min_wide:
            mov     r8, zstatus_minutes     ; reload -- see the stash above
            lda     r8
            phi     rf
            ldn     r8
            plo     rf
            call    zstatus_print_signed

zsd_done:
            mov     rd, zstatus_esc_normal
            call    zterm_print_string
            mov     rd, zstatus_esc_restore
            call    zterm_print_string

            mov     r8, zstatus_had_error
            ldn     r8
            lbz     zsd_ok
            stc
            rtn
zsd_ok:
            clc
            rtn
            endp

; zstatus_print_signed (internal): RF = signed 16-bit value (set
; immediately before the call). Prints it in decimal, with a leading
; '-' if negative -- same negate-then-format approach as zdisp_
; print_num in lib/zdispatch.asm.
            proc    zstatus_print_signed
            ghi     rf
            ani     $80
            lbz     zsps_positive

            ghi     rf
            not
            phi     rf
            glo     rf
            not
            plo     rf
            add16   rf, 1               ; rf = magnitude

            mov     r8, zstatus_numbuf
            ldi     '-'
            str     r8                  ; zstatus_numbuf[0] = '-' --
                                        ; ym_fmt_uint32 below writes
                                        ; its own digits starting one
                                        ; byte further in, so the whole
                                        ; "-1234" can be printed in a
                                        ; single call afterward; no
                                        ; need to print the sign
                                        ; separately and hope the
                                        ; magnitude survives an
                                        ; intervening kernel call (the
                                        ; same class of bug as
                                        ; zdisp_restore_game's own --
                                        ; K_TYPE's clobber footprint
                                        ; isn't documented either)
            mov     r8, rf              ; r8 = magnitude (low word)
            ldi     0
            phi     rd
            plo     rd                  ; rd = 0 (high word -- a
                                        ; Z-machine global's own
                                        ; magnitude never exceeds
                                        ; 32768)
            mov     rf, zstatus_numbuf
            add16   rf, 1               ; rf = numbuf+1: write digits
                                        ; right after the '-'
            call    ym_fmt_uint32

            mov     rd, zstatus_numbuf  ; print the whole "-1234" at
            call    zterm_print_string  ; once
            rtn

zsps_positive:
            mov     r8, rf              ; r8 = value's low word
            ldi     0
            phi     rd
            plo     rd
            mov     rf, zstatus_numbuf
            call    ym_fmt_uint32

            mov     rd, zstatus_numbuf
            call    zterm_print_string
            rtn
            endp

            proc    _zstatus_data
zstatus_columns:        dw      80
zstatus_rows:            dw      24
zstatus_had_error:       db      0
zstatus_buf:             ds      512
zstatus_numbuf:          ds      12
zstatus_minutes:         dw      0   ; the minutes value, held across
                                     ; the zero-pad's own K_TYPE call
zstatus_env_columns:     db      "COLUMNS",0
zstatus_env_rows:        db      "ROWS",0
zstatus_esc_save:        db      27,"[s",0
zstatus_esc_restore:     db      27,"[u",0
zstatus_esc_home:        db      27,"[1;1H",0
zstatus_esc_reverse:     db      27,"[7m",0
zstatus_esc_normal:      db      27,"[0m",0
zstatus_esc_clear:       db      27,"[2K",0
zstatus_esc_col_prefix:  db      27,"[",0
zstatus_label_score:     db      "Score: ",0
zstatus_label_moves:     db      "  Moves: ",0
zstatus_label_time:      db      "Time: ",0
                public  zstatus_columns
                public  zstatus_rows
                public  zstatus_had_error
                public  zstatus_buf
                public  zstatus_numbuf
                public  zstatus_minutes
                public  zstatus_env_columns
                public  zstatus_env_rows
                public  zstatus_esc_save
                public  zstatus_esc_restore
                public  zstatus_esc_home
                public  zstatus_esc_reverse
                public  zstatus_esc_normal
                public  zstatus_esc_clear
                public  zstatus_esc_col_prefix
                public  zstatus_label_score
                public  zstatus_label_moves
                public  zstatus_label_time
            endp
