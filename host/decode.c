#include "decode.h"

enum { DECODE_OK = 0, DECODE_ERROR = -1 };

/* Per-(category, opcode-number) metadata: does this opcode store a
 * result, branch, or (0OP print/print_ret only) carry an inline
 * packed string? This is purely about instruction *shape* -- what
 * trailing bytes follow the operands -- not opcode semantics, which
 * belongs to dispatch, not decode. Opcodes decode doesn't recognize
 * (V4+/V5+ opcodes, or simply unassigned in V3) default to "none of
 * the above": decode never fails on an opcode number it doesn't know,
 * only on a malformed instruction (see decode_instruction's own
 * comment) -- recognizing and rejecting an opcode is dispatch's job.
 */
struct opcode_shape {
    unsigned char stores;
    unsigned char branches;
    unsigned char has_text;
};

static const struct opcode_shape shape_2op[32] = {
    /*  0 */ {0, 0, 0},
    /*  1 je          */ {0, 1, 0},
    /*  2 jl          */ {0, 1, 0},
    /*  3 jg          */ {0, 1, 0},
    /*  4 dec_chk     */ {0, 1, 0},
    /*  5 inc_chk     */ {0, 1, 0},
    /*  6 jin         */ {0, 1, 0},
    /*  7 test        */ {0, 1, 0},
    /*  8 or          */ {1, 0, 0},
    /*  9 and         */ {1, 0, 0},
    /* 10 test_attr   */ {0, 1, 0},
    /* 11 set_attr    */ {0, 0, 0},
    /* 12 clear_attr  */ {0, 0, 0},
    /* 13 store       */ {0, 0, 0},
    /* 14 insert_obj  */ {0, 0, 0},
    /* 15 loadw       */ {1, 0, 0},
    /* 16 loadb       */ {1, 0, 0},
    /* 17 get_prop    */ {1, 0, 0},
    /* 18 get_prop_addr */ {1, 0, 0},
    /* 19 get_next_prop */ {1, 0, 0},
    /* 20 add         */ {1, 0, 0},
    /* 21 sub         */ {1, 0, 0},
    /* 22 mul         */ {1, 0, 0},
    /* 23 div         */ {1, 0, 0},
    /* 24 mod         */ {1, 0, 0},
    /* 25-31: not in V3 */
    {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}
};

static const struct opcode_shape shape_1op[16] = {
    /*  0 jz          */ {0, 1, 0},
    /*  1 get_sibling */ {1, 1, 0},
    /*  2 get_child   */ {1, 1, 0},
    /*  3 get_parent  */ {1, 0, 0},
    /*  4 get_prop_len */ {1, 0, 0},
    /*  5 inc         */ {0, 0, 0},
    /*  6 dec         */ {0, 0, 0},
    /*  7 print_addr  */ {0, 0, 0},
    /*  8: not in V3  */ {0, 0, 0},
    /*  9 remove_obj  */ {0, 0, 0},
    /* 10 print_obj   */ {0, 0, 0},
    /* 11 ret         */ {0, 0, 0},
    /* 12 jump        */ {0, 0, 0},
    /* 13 print_paddr */ {0, 0, 0},
    /* 14 load        */ {1, 0, 0},
    /* 15 not         */ {1, 0, 0}
};

static const struct opcode_shape shape_0op[16] = {
    /*  0 rtrue       */ {0, 0, 0},
    /*  1 rfalse      */ {0, 0, 0},
    /*  2 print       */ {0, 0, 1},
    /*  3 print_ret   */ {0, 0, 1},
    /*  4 nop         */ {0, 0, 0},
    /*  5 save        */ {0, 1, 0},
    /*  6 restore     */ {0, 1, 0},
    /*  7 restart     */ {0, 0, 0},
    /*  8 ret_popped  */ {0, 0, 0},
    /*  9 pop         */ {0, 0, 0},
    /* 10 quit        */ {0, 0, 0},
    /* 11 new_line    */ {0, 0, 0},
    /* 12 show_status */ {0, 0, 0},
    /* 13 verify      */ {0, 1, 0},
    /* 14: not in V3  */ {0, 0, 0},
    /* 15: not in V3  */ {0, 0, 0}
};

static const struct opcode_shape shape_var[32] = {
    /*  0 call        */ {1, 0, 0},
    /*  1 storew      */ {0, 0, 0},
    /*  2 storeb      */ {0, 0, 0},
    /*  3 put_prop    */ {0, 0, 0},
    /*  4 sread       */ {0, 0, 0},
    /*  5 print_char  */ {0, 0, 0},
    /*  6 print_num   */ {0, 0, 0},
    /*  7 random      */ {1, 0, 0},
    /*  8 push        */ {0, 0, 0},
    /*  9 pull        */ {0, 0, 0},
    /* 10 split_window */ {0, 0, 0},
    /* 11 set_window  */ {0, 0, 0},
    /* 12-18: not in V3 */
    {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0},
    /* 19 output_stream */ {0, 0, 0},
    /* 20 input_stream */ {0, 0, 0},
    /* 21-31: not in V3 */
    {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0},
    {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}, {0, 0, 0}
};

static const struct opcode_shape *shape_for(enum instruction_category category,
                                            uint8_t opcode)
{
    switch (category) {
    case CATEGORY_2OP: return opcode < 32 ? &shape_2op[opcode] : 0;
    case CATEGORY_1OP: return opcode < 16 ? &shape_1op[opcode] : 0;
    case CATEGORY_0OP: return opcode < 16 ? &shape_0op[opcode] : 0;
    case CATEGORY_VAR: return opcode < 32 ? &shape_var[opcode] : 0;
    }
    return 0;
}

static int read_byte(const struct story_mem *memory, uint16_t *addr,
                     uint8_t *value)
{
    if (story_mem_read8(memory, *addr, value) != 0) {
        return DECODE_ERROR;
    }
    *addr = (uint16_t)(*addr + 1);
    return DECODE_OK;
}

static int read_word(const struct story_mem *memory, uint16_t *addr,
                     uint16_t *value)
{
    if (story_mem_read16(memory, *addr, value) != 0) {
        return DECODE_ERROR;
    }
    *addr = (uint16_t)(*addr + 2);
    return DECODE_OK;
}

static enum operand_type decode_operand_type(uint8_t bits)
{
    if (bits == 0) return OPERAND_LARGE;
    if (bits == 1) return OPERAND_SMALL;
    return OPERAND_VARIABLE;
}

static int read_operand(const struct story_mem *memory, uint16_t *addr,
                        enum operand_type type, uint16_t *value)
{
    uint8_t byte;

    if (type == OPERAND_LARGE) {
        return read_word(memory, addr, value);
    }
    if (read_byte(memory, addr, &byte) != DECODE_OK) {
        return DECODE_ERROR;
    }
    *value = byte;
    return DECODE_OK;
}

int decode_instruction(const struct story_mem *memory, uint16_t addr,
                       struct instruction *instr)
{
    uint16_t cursor;
    uint8_t opcode_byte;
    const struct opcode_shape *shape;
    uint8_t i;

    if (memory == 0 || instr == 0) {
        return DECODE_ERROR;
    }
    cursor = addr;
    if (read_byte(memory, &cursor, &opcode_byte) != DECODE_OK) {
        return DECODE_ERROR;
    }
    instr->addr = addr;
    instr->operand_count = 0;
    instr->has_text = 0;

    if ((opcode_byte & 0xc0) == 0xc0) {
        instr->form = FORM_VARIABLE;
        instr->category = (opcode_byte & 0x20) ? CATEGORY_VAR : CATEGORY_2OP;
        instr->opcode = (uint8_t)(opcode_byte & 0x1f);

        {
            uint8_t types_byte;
            uint8_t shift;

            if (read_byte(memory, &cursor, &types_byte) != DECODE_OK) {
                return DECODE_ERROR;
            }
            for (shift = 0; shift < 8; shift += 2) {
                uint8_t bits = (uint8_t)((types_byte >> (6 - shift)) & 0x3);

                if (bits == 3) {
                    break;
                }
                instr->operand_types[instr->operand_count++] =
                    decode_operand_type(bits);
            }
        }
    } else if ((opcode_byte & 0xc0) == 0x80) {
        uint8_t optype_bits = (uint8_t)((opcode_byte >> 4) & 0x3);

        instr->form = FORM_SHORT;
        instr->opcode = (uint8_t)(opcode_byte & 0xf);
        if (optype_bits == 3) {
            instr->category = CATEGORY_0OP;
        } else {
            instr->category = CATEGORY_1OP;
            instr->operand_types[0] = decode_operand_type(optype_bits);
            instr->operand_count = 1;
        }
    } else {
        instr->form = FORM_LONG;
        instr->category = CATEGORY_2OP;
        instr->opcode = (uint8_t)(opcode_byte & 0x1f);
        instr->operand_types[0] =
            (opcode_byte & 0x40) ? OPERAND_VARIABLE : OPERAND_SMALL;
        instr->operand_types[1] =
            (opcode_byte & 0x20) ? OPERAND_VARIABLE : OPERAND_SMALL;
        instr->operand_count = 2;
    }

    for (i = 0; i < instr->operand_count; ++i) {
        if (read_operand(memory, &cursor, instr->operand_types[i],
                         &instr->operands[i]) != DECODE_OK) {
            return DECODE_ERROR;
        }
    }

    shape = shape_for(instr->category, instr->opcode);
    instr->stores = shape != 0 && shape->stores;
    instr->branches = shape != 0 && shape->branches;
    if (shape != 0 && shape->has_text) {
        instr->has_text = 1;
    }

    if (instr->stores) {
        uint8_t store_variable;

        if (read_byte(memory, &cursor, &store_variable) != DECODE_OK) {
            return DECODE_ERROR;
        }
        instr->store_variable = store_variable;
    }

    if (instr->branches) {
        uint8_t branch1;

        if (read_byte(memory, &cursor, &branch1) != DECODE_OK) {
            return DECODE_ERROR;
        }
        instr->branch_on_true = (branch1 & 0x80) != 0;
        if (branch1 & 0x40) {
            instr->branch_offset = (int16_t)(branch1 & 0x3f);
        } else {
            uint8_t branch2;
            int16_t offset;

            if (read_byte(memory, &cursor, &branch2) != DECODE_OK) {
                return DECODE_ERROR;
            }
            offset = (int16_t)(((branch1 & 0x3f) << 8) | branch2);
            if (offset & 0x2000) {
                offset = (int16_t)(offset - 0x4000);
            }
            instr->branch_offset = offset;
        }
    }

    if (instr->has_text) {
        for (;;) {
            uint16_t word;

            if (read_word(memory, &cursor, &word) != DECODE_OK) {
                return DECODE_ERROR;
            }
            if (word & 0x8000u) {
                break;
            }
        }
    }

    instr->length = (uint16_t)(cursor - addr);
    return DECODE_OK;
}
