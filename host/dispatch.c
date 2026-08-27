#include "dispatch.h"

#include "decode.h"

enum { VM_OK = 0, VM_ERROR = -1 };

static int do_return(struct vm_context *ctx, uint16_t value)
{
    struct vm_frame frame;

    if (vm_frame_pop(ctx->state, &frame) != VM_OK) {
        return VM_ERROR;
    }
    ctx->state->pc = frame.return_pc;
    return vm_write_variable(ctx->state, ctx->memory, frame.store_variable,
                             value) == 0 ? VM_OK : VM_ERROR;
}

static int do_branch(struct vm_context *ctx, const struct instruction *instr,
                     int condition)
{
    uint16_t after;

    if ((condition != 0) != (instr->branch_on_true != 0)) {
        return VM_OK;               /* not taken: pc is already past
                                     * this instruction */
    }
    if (instr->branch_offset == 0) {
        return do_return(ctx, 0);
    }
    if (instr->branch_offset == 1) {
        return do_return(ctx, 1);
    }
    after = (uint16_t)(instr->addr + instr->length);
    ctx->state->pc = (uint16_t)(after + instr->branch_offset - 2);
    return VM_OK;
}

static int do_call(struct vm_context *ctx, const uint16_t *operand,
                   uint8_t operand_count, uint8_t store_variable,
                   uint16_t return_pc)
{
    uint16_t routine_addr;
    uint8_t local_count;
    uint16_t locals[VM_LOCALS_MAX];
    int i;

    if (operand_count == 0) {
        return VM_ERROR;            /* "call 0" (returns false without
                                     * a real call) isn't implemented
                                     * in this proof-of-concept slice */
    }
    routine_addr = (uint16_t)(operand[0] * 2);     /* V3 packing */

    if (story_mem_read8(ctx->memory, routine_addr, &local_count) != 0 ||
        local_count > VM_LOCALS_MAX) {
        return VM_ERROR;
    }
    for (i = 0; i < local_count; ++i) {
        if (story_mem_read16(ctx->memory,
                             (uint16_t)(routine_addr + 1 + i * 2),
                             &locals[i]) != 0) {
            return VM_ERROR;
        }
    }
    for (i = 1; i < operand_count && (i - 1) < local_count; ++i) {
        locals[i - 1] = operand[i];        /* arguments override the
                                            * routine's own defaults */
    }

    if (vm_frame_push(ctx->state, return_pc, store_variable,
                      (uint8_t)(operand_count - 1), locals,
                      local_count) != 0) {
        return VM_ERROR;
    }
    ctx->state->pc = (uint16_t)(routine_addr + 1 + local_count * 2);
    return VM_OK;
}

static int resolve_operand(struct vm_context *ctx, enum operand_type type,
                           uint16_t raw, uint16_t *value)
{
    if (type == OPERAND_VARIABLE) {
        return vm_read_variable(ctx->state, ctx->memory, (uint8_t)raw, value);
    }
    *value = raw;
    return VM_OK;
}

int vm_step(struct vm_context *ctx)
{
    struct instruction instr;
    uint16_t operand[DECODE_MAX_OPERANDS];
    uint16_t next_pc;
    int i;

    if (ctx == 0 || ctx->memory == 0 || ctx->state == 0) {
        return VM_ERROR;
    }
    if (decode_instruction(ctx->memory, ctx->state->pc, &instr) != 0) {
        return VM_ERROR;
    }
    for (i = 0; i < instr.operand_count; ++i) {
        if (resolve_operand(ctx, instr.operand_types[i], instr.operands[i],
                            &operand[i]) != VM_OK) {
            return VM_ERROR;
        }
    }

    next_pc = (uint16_t)(instr.addr + instr.length);
    ctx->state->pc = next_pc;      /* default: fall through -- a jump/
                                    * call/return/taken branch below
                                    * overrides this */

    if (instr.category == CATEGORY_2OP) {
        switch (instr.opcode) {
        case 1:                     /* je: true if any later operand
                                     * equals the first */
            {
                int equal = 0;
                int j;

                for (j = 1; j < instr.operand_count; ++j) {
                    if (operand[0] == operand[j]) {
                        equal = 1;
                        break;
                    }
                }
                return do_branch(ctx, &instr, equal);
            }
        case 13:                    /* store: operand[0] is a variable
                                     * NUMBER (indirect access) */
            return vm_write_variable_indirect(ctx->state, ctx->memory,
                (uint8_t)operand[0], operand[1]) == 0 ? VM_OK : VM_ERROR;
        case 20:                    /* add */
            return vm_write_variable(ctx->state, ctx->memory,
                instr.store_variable,
                (uint16_t)(operand[0] + operand[1])) == 0 ? VM_OK : VM_ERROR;
        case 21:                    /* sub */
            return vm_write_variable(ctx->state, ctx->memory,
                instr.store_variable,
                (uint16_t)(operand[0] - operand[1])) == 0 ? VM_OK : VM_ERROR;
        default:
            return VM_ERROR;
        }
    }

    if (instr.category == CATEGORY_1OP) {
        switch (instr.opcode) {
        case 0:                     /* jz */
            return do_branch(ctx, &instr, operand[0] == 0);
        case 11:                    /* ret */
            return do_return(ctx, operand[0]);
        case 12:                    /* jump: unconditional, same
                                     * +offset-2 rule as a taken
                                     * branch, but operand is a plain
                                     * signed word, not branch data */
            ctx->state->pc =
                (uint16_t)(next_pc + (int16_t)operand[0] - 2);
            return VM_OK;
        default:
            return VM_ERROR;
        }
    }

    if (instr.category == CATEGORY_0OP) {
        switch (instr.opcode) {
        case 0:                     /* rtrue */
            return do_return(ctx, 1);
        case 1:                     /* rfalse */
            return do_return(ctx, 0);
        case 2:                     /* print: the inline string is
                                     * everything after the opcode
                                     * byte, decode already measured it */
            return ztext_decode(ctx->memory->image + instr.addr + 1,
                (uint16_t)(instr.length - 1), ctx->emit,
                ctx->emit_context) == 0 ? VM_OK : VM_ERROR;
        case 10:                    /* quit */
            ctx->quit = 1;
            return VM_OK;
        case 11:                    /* new_line */
            return ctx->emit('\n', ctx->emit_context) == 0 ?
                VM_OK : VM_ERROR;
        default:
            return VM_ERROR;
        }
    }

    if (instr.category == CATEGORY_VAR) {
        switch (instr.opcode) {
        case 0:                     /* call */
            return do_call(ctx, operand, instr.operand_count,
                           instr.store_variable, next_pc);
        default:
            return VM_ERROR;
        }
    }

    return VM_ERROR;
}
