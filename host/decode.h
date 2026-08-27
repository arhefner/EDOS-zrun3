#ifndef ZRUN3_DECODE_H
#define ZRUN3_DECODE_H

#include <stdint.h>

#include "story_mem.h"

#define DECODE_MAX_OPERANDS 4

enum operand_type {
    OPERAND_LARGE,      /* 2-byte constant */
    OPERAND_SMALL,      /* 1-byte constant */
    OPERAND_VARIABLE    /* 1-byte variable number */
};

enum instruction_form {
    FORM_LONG,          /* always 2OP */
    FORM_SHORT,         /* 0OP or 1OP */
    FORM_VARIABLE       /* 2OP or VAR, per the opcode byte's own bit 5 */
};

enum instruction_category {
    CATEGORY_0OP,
    CATEGORY_1OP,
    CATEGORY_2OP,
    CATEGORY_VAR
};

struct instruction {
    uint16_t addr;                          /* where this was read from */
    uint16_t length;                        /* total bytes consumed */
    enum instruction_form form;
    enum instruction_category category;
    uint8_t opcode;                         /* number within its category */

    uint8_t operand_count;
    enum operand_type operand_types[DECODE_MAX_OPERANDS];
    uint16_t operands[DECODE_MAX_OPERANDS];

    int stores;
    uint8_t store_variable;

    int branches;
    int branch_on_true;                     /* branch when the condition
                                             * is true (1) or false (0) */
    int16_t branch_offset;                  /* 0 = return false, 1 =
                                             * return true, else signed
                                             * jump offset */

    int has_text;                           /* 0OP print/print_ret: an
                                             * inline packed string
                                             * follows, ending where
                                             * `length` says */
};

/* Decodes the V3 instruction at addr, filling in `instr`, including
 * its operands, store/branch data, and total length (so the caller
 * can advance the PC by instr->length without re-deriving it).
 * Returns -1 for a malformed instruction (an operand or branch/store
 * byte would run past `length`, the memory image's own bound) --
 * never for an opcode number decode_instruction doesn't recognize,
 * since recognizing opcodes is dispatch's job, not decode's. */
int decode_instruction(const struct story_mem *memory, uint16_t addr,
                       struct instruction *instr);

#endif
