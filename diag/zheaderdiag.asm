;
; zheaderdiag.asm - self-contained diagnostic for the V3 header parser
; (zheader.asm)
;
; check 0 reuses ZORK I's own real 64-byte header verbatim (extracted
; directly from the story file, not hand-constructed) -- parses it and
; asserts every field against values independently computed from the
; same file with a Python script, not just eyeballed. check 1 corrupts
; the version byte; check 2 corrupts the header so object_table falls
; outside dynamic memory (object_table set past dynamic_end) -- both
; must be rejected (DF=1). Touches no ELF-DOS kernel or BIOS entry
; points: zheader_parse takes a plain host buffer, no file I/O of its
; own.
;

#include    include/opcodes.def

            extrn   zheader_parse
            extrn   zheader_initial_pc
            extrn   zheader_dictionary
            extrn   zheader_object_table
            extrn   zheader_globals
            extrn   zheader_dynamic_end
            extrn   zheader_high_memory
            extrn   zheader_abbrev_table

            extrn   zh_zork1_header
            extrn   zh_bad_version
            extrn   zh_bad_ordering
            extrn   zh_results

ZHEADERDIAG_COUNT:      equ     3

            proc    zhdiag_run

; check 0: real ZORK I header parses successfully with every field
; matching the story file's own actual values
            mov     rd, zh_zork1_header
            call    zheader_parse
            lbdf    zh_fail0

            mov     rf, zheader_initial_pc
            lda     rf
            xri     $4f
            lbnz    zh_fail0
            ldn     rf
            xri     $05
            lbnz    zh_fail0

            mov     rf, zheader_dictionary
            lda     rf
            xri     $3b
            lbnz    zh_fail0
            ldn     rf
            xri     $21
            lbnz    zh_fail0

            mov     rf, zheader_object_table
            lda     rf
            xri     $02
            lbnz    zh_fail0
            ldn     rf
            xri     $b0
            lbnz    zh_fail0

            mov     rf, zheader_globals
            lda     rf
            xri     $22
            lbnz    zh_fail0
            ldn     rf
            xri     $71
            lbnz    zh_fail0

            mov     rf, zheader_dynamic_end
            lda     rf
            xri     $2e
            lbnz    zh_fail0
            ldn     rf
            xri     $53
            lbnz    zh_fail0

            mov     rf, zheader_high_memory
            lda     rf
            xri     $4e
            lbnz    zh_fail0
            ldn     rf
            xri     $37
            lbnz    zh_fail0

            mov     rf, zheader_abbrev_table
            lda     rf
            xri     $01
            lbnz    zh_fail0
            ldn     rf
            xri     $f0
            lbnz    zh_fail0

            mov     rb, zh_results+0
            ldi     0
            lbr     zh_store0
zh_fail0:   mov     rb, zh_results+0
            ldi     1
zh_store0:  str     rb

; check 1: version byte corrupted (4, not 3) -- rejected
            mov     rd, zh_bad_version
            call    zheader_parse
            lbnf    zh_fail1            ; expect DF=1
            mov     rb, zh_results+1
            ldi     0
            lbr     zh_store1
zh_fail1:   mov     rb, zh_results+1
            ldi     1
zh_store1:  str     rb

; check 2: object_table corrupted to fall outside dynamic memory --
; rejected
            mov     rd, zh_bad_ordering
            call    zheader_parse
            lbnf    zh_fail2            ; expect DF=1
            mov     rb, zh_results+2
            ldi     0
            lbr     zh_store2
zh_fail2:   mov     rb, zh_results+2
            ldi     1
zh_store2:  str     rb

; tally failures into RF, DF=1 if any
            mov     rb, zh_results
            ldi     ZHEADERDIAG_COUNT
            plo     r9
            ldi     0
            plo     rf
            phi     rf
zh_tally:
            lda     rb
            lbz     zh_tally_next
            inc     rf
zh_tally_next:
            dec     r9
            glo     r9
            lbnz    zh_tally
            glo     rf
            lbnz    zh_fail_return
            clc
            rtn
zh_fail_return:
            stc
            rtn
            endp

            proc    _zheaderdiag_data
zh_zork1_header: db    $03,$00,$00,$58,$4e,$37,$4f,$05,$3b,$21,$02,$b0,$22,$71,$2e,$53
                 db    $00,$00,$38,$34,$30,$37,$32,$36,$01,$f0,$a5,$c6,$a1,$29,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
zh_bad_version:  db    $04,$00,$00,$58,$4e,$37,$4f,$05,$3b,$21,$02,$b0,$22,$71,$2e,$53
                 db    $00,$00,$38,$34,$30,$37,$32,$36,$01,$f0,$a5,$c6,$a1,$29,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
zh_bad_ordering: db    $03,$00,$00,$58,$4e,$37,$4f,$05,$3b,$21,$ff,$ff,$22,$71,$2e,$53
                 db    $00,$00,$38,$34,$30,$37,$32,$36,$01,$f0,$a5,$c6,$a1,$29,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
                 db    $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
zh_results:      ds    ZHEADERDIAG_COUNT
                public  zh_zork1_header
                public  zh_bad_version
                public  zh_bad_ordering
                public  zh_results
            endp
