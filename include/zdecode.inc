;
; zdecode.inc - V3 instruction buffer layout
;
; Shared between lib/zdecode.asm (which fills a buffer with this
; layout) and the not-yet-written dispatch port (which will read
; one). Mirrors host/decode.h's struct instruction field-for-field --
; see that header for what each field means; this file only pins down
; where each field lives in the ZDI_SIZE-byte buffer a caller passes
; to zdecode_instruction.
;

ZDI_ADDR:               equ     0       ; word
ZDI_LENGTH:              equ     2       ; word
ZDI_FORM:                equ     4       ; byte: 0=long,1=short,2=variable
ZDI_CATEGORY:            equ     5       ; byte: 0=0OP,1=1OP,2=2OP,3=VAR
ZDI_OPCODE:               equ     6       ; byte
ZDI_OPERAND_COUNT:        equ     7       ; byte
ZDI_OPERAND_TYPES:        equ     8       ; 4 bytes: 0=large,1=small,2=variable
ZDI_OPERANDS:             equ     12      ; 4 words
ZDI_STORES:               equ     20      ; byte, 0/1
ZDI_STORE_VARIABLE:       equ     21      ; byte
ZDI_BRANCHES:             equ     22      ; byte, 0/1
ZDI_BRANCH_ON_TRUE:       equ     23      ; byte, 0/1
ZDI_BRANCH_OFFSET:        equ     24      ; word, signed (0=return
                                          ; false, 1=return true, else
                                          ; a signed jump offset)
ZDI_HAS_TEXT:             equ     26      ; byte, 0/1
ZDI_SIZE:                 equ     27

ZDI_FORM_LONG:            equ     0
ZDI_FORM_SHORT:           equ     1
ZDI_FORM_VARIABLE:        equ     2

ZDI_CAT_0OP:              equ     0
ZDI_CAT_1OP:              equ     1
ZDI_CAT_2OP:              equ     2
ZDI_CAT_VAR:              equ     3
