#include "dispatch.h"

#include "decode.h"
#include "objects.h"
#include "parser.h"
#include "properties.h"

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

static int store_result(struct vm_context *ctx, uint8_t variable,
                        uint16_t value)
{
    return vm_write_variable(ctx->state, ctx->memory, variable, value) == 0 ?
        VM_OK : VM_ERROR;
}

/* Every character a "print"-family opcode produces funnels through
 * here, so "output_stream(3, table)" can redirect it into a memory
 * table instead of ctx->emit -- matching the Z-machine standard's
 * "any output produced is not seen ... in the current stream" wording
 * for a redirected stream. vm_emit_wrapper adapts this to ztext_decode's
 * own emit_fn shape for the print-family opcodes that decode z-text. */
static int vm_emit(struct vm_context *ctx, char c)
{
    if (ctx->output_table_active) {
        uint16_t addr = (uint16_t)(ctx->output_table + 2 +
                                   ctx->output_table_count);

        if (story_mem_write8(ctx->memory, addr, (uint8_t)c) != 0) {
            return -1;
        }
        ++ctx->output_table_count;
        return 0;
    }
    return ctx->emit(c, ctx->emit_context);
}

static int vm_emit_wrapper(char c, void *context)
{
    return vm_emit(context, c);
}

/* print_addr/print_paddr/print_obj don't know their string's length up
 * front the way decode_instruction measures an inline one -- pass a
 * generous bound (everything left in the story) and let ztext_decode's
 * own end-of-string bit stop it at the real end. */
static int print_ztext_at(struct vm_context *ctx, uint16_t addr)
{
    uint16_t remaining;

    if (addr > ctx->memory->length) {
        return VM_ERROR;
    }
    remaining = (uint16_t)((ctx->memory->length - addr) & ~1u);
    return ztext_decode(ctx->memory->image + addr, remaining,
                        vm_emit_wrapper, ctx) == 0 ? VM_OK : VM_ERROR;
}

static int emit_decimal(struct vm_context *ctx, int16_t value)
{
    char digits[6];
    int count = 0;
    uint16_t magnitude;
    int i;

    if (value < 0) {
        if (vm_emit(ctx, '-') != 0) {
            return VM_ERROR;
        }
        magnitude = (uint16_t)(-(int32_t)value);
    } else {
        magnitude = (uint16_t)value;
    }
    if (magnitude == 0) {
        return vm_emit(ctx, '0') == 0 ? VM_OK : VM_ERROR;
    }
    while (magnitude > 0) {
        digits[count++] = (char)('0' + magnitude % 10);
        magnitude = (uint16_t)(magnitude / 10);
    }
    for (i = count - 1; i >= 0; --i) {
        if (vm_emit(ctx, digits[i]) != 0) {
            return VM_ERROR;
        }
    }
    return VM_OK;
}

static int step_2op(struct vm_context *ctx, const struct instruction *instr,
                    const uint16_t *operand)
{
    switch (instr->opcode) {
    case 1:                     /* je: true if any later operand
                                 * equals the first */
        {
            int equal = 0;
            int j;

            for (j = 1; j < instr->operand_count; ++j) {
                if (operand[0] == operand[j]) {
                    equal = 1;
                    break;
                }
            }
            return do_branch(ctx, instr, equal);
        }
    case 2:                     /* jl */
        return do_branch(ctx, instr,
            (int16_t)operand[0] < (int16_t)operand[1]);
    case 3:                     /* jg */
        return do_branch(ctx, instr,
            (int16_t)operand[0] > (int16_t)operand[1]);
    case 4:                     /* dec_chk: operand[0] is a variable
                                 * NUMBER (already resolved normally,
                                 * used here indirectly) */
        {
            uint16_t current;
            int16_t updated;

            if (vm_read_variable_indirect(ctx->state, ctx->memory,
                                          (uint8_t)operand[0],
                                          &current) != 0) {
                return VM_ERROR;
            }
            updated = (int16_t)(current - 1);
            if (vm_write_variable_indirect(ctx->state, ctx->memory,
                                           (uint8_t)operand[0],
                                           (uint16_t)updated) != 0) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, updated < (int16_t)operand[1]);
        }
    case 5:                     /* inc_chk */
        {
            uint16_t current;
            int16_t updated;

            if (vm_read_variable_indirect(ctx->state, ctx->memory,
                                          (uint8_t)operand[0],
                                          &current) != 0) {
                return VM_ERROR;
            }
            updated = (int16_t)(current + 1);
            if (vm_write_variable_indirect(ctx->state, ctx->memory,
                                           (uint8_t)operand[0],
                                           (uint16_t)updated) != 0) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, updated > (int16_t)operand[1]);
        }
    case 6:                     /* jin: is operand[0]'s parent
                                 * operand[1]? */
        {
            uint8_t parent;

            if (obj_get_parent(ctx->memory, ctx->object_table,
                               (uint8_t)operand[0], &parent) != 0) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, parent == (uint8_t)operand[1]);
        }
    case 7:                     /* test: all flag bits set in bitmap? */
        return do_branch(ctx, instr,
            (operand[0] & operand[1]) == operand[1]);
    case 8:                     /* or */
        return store_result(ctx, instr->store_variable,
            (uint16_t)(operand[0] | operand[1]));
    case 9:                     /* and */
        return store_result(ctx, instr->store_variable,
            (uint16_t)(operand[0] & operand[1]));
    case 10:                    /* test_attr */
        {
            int is_set;

            if (obj_test_attr(ctx->memory, ctx->object_table,
                              (uint8_t)operand[0], (uint8_t)operand[1],
                              &is_set) != 0) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, is_set);
        }
    case 11:                    /* set_attr */
        return obj_set_attr(ctx->memory, ctx->object_table,
            (uint8_t)operand[0], (uint8_t)operand[1]) == 0 ?
            VM_OK : VM_ERROR;
    case 12:                    /* clear_attr */
        return obj_clear_attr(ctx->memory, ctx->object_table,
            (uint8_t)operand[0], (uint8_t)operand[1]) == 0 ?
            VM_OK : VM_ERROR;
    case 13:                    /* store: operand[0] is a variable
                                 * NUMBER (indirect access) */
        return vm_write_variable_indirect(ctx->state, ctx->memory,
            (uint8_t)operand[0], operand[1]) == 0 ? VM_OK : VM_ERROR;
    case 14:                    /* insert_obj */
        return obj_insert(ctx->memory, ctx->object_table,
            (uint8_t)operand[0], (uint8_t)operand[1]) == 0 ?
            VM_OK : VM_ERROR;
    case 15:                    /* loadw */
        {
            uint16_t value;

            if (story_mem_read16(ctx->memory,
                                 (uint16_t)(operand[0] + 2 * operand[1]),
                                 &value) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, value);
        }
    case 16:                    /* loadb */
        {
            uint8_t value;

            if (story_mem_read8(ctx->memory,
                                (uint16_t)(operand[0] + operand[1]),
                                &value) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, value);
        }
    case 17:                    /* get_prop */
        {
            uint16_t value;

            if (prop_get(ctx->memory, ctx->object_table,
                        (uint8_t)operand[0], (uint8_t)operand[1],
                        &value) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, value);
        }
    case 18:                    /* get_prop_addr */
        {
            uint16_t addr;

            if (prop_get_addr(ctx->memory, ctx->object_table,
                             (uint8_t)operand[0], (uint8_t)operand[1],
                             &addr) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, addr);
        }
    case 19:                    /* get_next_prop */
        {
            uint8_t next;

            if (prop_get_next(ctx->memory, ctx->object_table,
                             (uint8_t)operand[0], (uint8_t)operand[1],
                             &next) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, next);
        }
    case 20:                    /* add */
        return store_result(ctx, instr->store_variable,
            (uint16_t)(operand[0] + operand[1]));
    case 21:                    /* sub */
        return store_result(ctx, instr->store_variable,
            (uint16_t)(operand[0] - operand[1]));
    case 22:                    /* mul */
        return store_result(ctx, instr->store_variable,
            (uint16_t)((int16_t)operand[0] * (int16_t)operand[1]));
    case 23:                    /* div */
        if (operand[1] == 0) {
            return VM_ERROR;
        }
        return store_result(ctx, instr->store_variable,
            (uint16_t)((int16_t)operand[0] / (int16_t)operand[1]));
    case 24:                    /* mod */
        if (operand[1] == 0) {
            return VM_ERROR;
        }
        return store_result(ctx, instr->store_variable,
            (uint16_t)((int16_t)operand[0] % (int16_t)operand[1]));
    default:
        return VM_ERROR;
    }
}

static int step_1op(struct vm_context *ctx, const struct instruction *instr,
                    const uint16_t *operand)
{
    switch (instr->opcode) {
    case 0:                     /* jz */
        return do_branch(ctx, instr, operand[0] == 0);
    case 1:                     /* get_sibling */
        {
            uint8_t sibling;

            if (obj_get_sibling(ctx->memory, ctx->object_table,
                               (uint8_t)operand[0], &sibling) != 0) {
                return VM_ERROR;
            }
            if (store_result(ctx, instr->store_variable, sibling) != VM_OK) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, sibling != 0);
        }
    case 2:                     /* get_child */
        {
            uint8_t child;

            if (obj_get_child(ctx->memory, ctx->object_table,
                             (uint8_t)operand[0], &child) != 0) {
                return VM_ERROR;
            }
            if (store_result(ctx, instr->store_variable, child) != VM_OK) {
                return VM_ERROR;
            }
            return do_branch(ctx, instr, child != 0);
        }
    case 3:                     /* get_parent */
        {
            uint8_t parent;

            if (obj_get_parent(ctx->memory, ctx->object_table,
                              (uint8_t)operand[0], &parent) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, parent);
        }
    case 4:                     /* get_prop_len */
        {
            uint8_t len;

            if (prop_get_len(ctx->memory, operand[0], &len) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, len);
        }
    case 5:                     /* inc: operand[0] is a variable
                                 * NUMBER, used indirectly */
        {
            uint16_t current;

            if (vm_read_variable_indirect(ctx->state, ctx->memory,
                                          (uint8_t)operand[0],
                                          &current) != 0) {
                return VM_ERROR;
            }
            return vm_write_variable_indirect(ctx->state, ctx->memory,
                (uint8_t)operand[0], (uint16_t)(current + 1)) == 0 ?
                VM_OK : VM_ERROR;
        }
    case 6:                     /* dec */
        {
            uint16_t current;

            if (vm_read_variable_indirect(ctx->state, ctx->memory,
                                          (uint8_t)operand[0],
                                          &current) != 0) {
                return VM_ERROR;
            }
            return vm_write_variable_indirect(ctx->state, ctx->memory,
                (uint8_t)operand[0], (uint16_t)(current - 1)) == 0 ?
                VM_OK : VM_ERROR;
        }
    case 7:                     /* print_addr */
        return print_ztext_at(ctx, operand[0]);
    case 9:                     /* remove_obj */
        return obj_remove(ctx->memory, ctx->object_table,
            (uint8_t)operand[0]) == 0 ? VM_OK : VM_ERROR;
    case 10:                    /* print_obj */
        {
            uint16_t addr;
            uint16_t length;

            if (obj_short_name(ctx->memory, ctx->object_table,
                              (uint8_t)operand[0], &addr, &length) != 0) {
                return VM_ERROR;
            }
            return ztext_decode(ctx->memory->image + addr, length,
                vm_emit_wrapper, ctx) == 0 ? VM_OK : VM_ERROR;
        }
    case 11:                    /* ret */
        return do_return(ctx, operand[0]);
    case 12:                    /* jump: unconditional, same
                                 * +offset-2 rule as a taken branch,
                                 * but operand is a plain signed word,
                                 * not branch data */
        ctx->state->pc = (uint16_t)(instr->addr + instr->length +
                                    (int16_t)operand[0] - 2);
        return VM_OK;
    case 13:                    /* print_paddr */
        return print_ztext_at(ctx, (uint16_t)(operand[0] * 2));
    case 14:                    /* load */
        {
            uint16_t value;

            if (vm_read_variable_indirect(ctx->state, ctx->memory,
                                          (uint8_t)operand[0],
                                          &value) != 0) {
                return VM_ERROR;
            }
            return store_result(ctx, instr->store_variable, value);
        }
    case 15:                    /* not */
        return store_result(ctx, instr->store_variable,
            (uint16_t)(~operand[0]));
    default:
        return VM_ERROR;
    }
}

static int step_0op(struct vm_context *ctx, const struct instruction *instr)
{
    switch (instr->opcode) {
    case 0:                     /* rtrue */
        return do_return(ctx, 1);
    case 1:                     /* rfalse */
        return do_return(ctx, 0);
    case 2:                     /* print: the inline string is
                                 * everything after the opcode byte,
                                 * decode already measured it */
        return ztext_decode(ctx->memory->image + instr->addr + 1,
            (uint16_t)(instr->length - 1), vm_emit_wrapper,
            ctx) == 0 ? VM_OK : VM_ERROR;
    case 3:                     /* print_ret: print, then a newline,
                                 * then return true */
        if (ztext_decode(ctx->memory->image + instr->addr + 1,
                         (uint16_t)(instr->length - 1), vm_emit_wrapper,
                         ctx) != 0 ||
            vm_emit(ctx, '\n') != 0) {
            return VM_ERROR;
        }
        return do_return(ctx, 1);
    case 5:                     /* save: on success, branches (per the
                                 * V1-3 encoding decode already parsed)
                                 * to capture the resumption point,
                                 * then hands that state to the save
                                 * callback; on failure the tentative
                                 * branch is undone and execution just
                                 * falls through normally */
        {
            uint16_t fallthrough_pc = ctx->state->pc;

            if (ctx->save == 0) {
                return VM_ERROR;
            }
            if (do_branch(ctx, instr, 1) != VM_OK) {
                return VM_ERROR;
            }
            if (ctx->save(ctx->state, ctx->memory->image,
                          ctx->memory->dynamic_end, ctx->save_context) != 0) {
                ctx->state->pc = fallthrough_pc;
            }
            return VM_OK;
        }
    case 6:                     /* restore: per the standard, "the
                                 * branch is never actually made" --
                                 * on success the callback overwrites
                                 * state (including pc) wholesale with
                                 * the point save captured; on failure
                                 * (or no restore source configured)
                                 * this just falls through normally,
                                 * same as any other failed branch */
        if (ctx->restore != 0) {
            ctx->restore(ctx->state, ctx->memory->image,
                        ctx->memory->dynamic_end, ctx->restore_context);
        }
        return VM_OK;
    case 7:                     /* restart: resets state and dynamic
                                 * memory to their initial values via a
                                 * caller-supplied callback -- only the
                                 * platform knows what "initial" means
                                 * (a pristine copy of the story kept
                                 * aside before play began) */
        if (ctx->restart == 0 ||
            ctx->restart(ctx->state, ctx->memory->image,
                        ctx->memory->dynamic_end, ctx->restart_context) != 0) {
            return VM_ERROR;
        }
        return VM_OK;
    case 8:                     /* ret_popped */
        {
            uint16_t value;

            if (vm_pop(ctx->state, &value) != 0) {
                return VM_ERROR;
            }
            return do_return(ctx, value);
        }
    case 9:                     /* pop: discard the top of the stack */
        {
            uint16_t discard;

            return vm_pop(ctx->state, &discard) == 0 ? VM_OK : VM_ERROR;
        }
    case 10:                    /* quit */
        ctx->quit = 1;
        return VM_OK;
    case 11:                    /* new_line */
        return vm_emit(ctx, '\n') == 0 ? VM_OK : VM_ERROR;
    case 12:                    /* show_status: real V3 interpreters
                                 * redraw a status bar here (location,
                                 * score, turns) -- a UI concern for
                                 * the platform terminal layer, not
                                 * this portable core, so it's a no-op */
        return VM_OK;
    default:
        return VM_ERROR;
    }
}

static int step_var(struct vm_context *ctx, const struct instruction *instr,
                    const uint16_t *operand, uint16_t next_pc)
{
    switch (instr->opcode) {
    case 0:                     /* call */
        return do_call(ctx, operand, instr->operand_count,
                       instr->store_variable, next_pc);
    case 1:                     /* storew */
        if (story_mem_write8(ctx->memory,
                             (uint16_t)(operand[0] + 2 * operand[1]),
                             (uint8_t)(operand[2] >> 8)) != 0 ||
            story_mem_write8(ctx->memory,
                             (uint16_t)(operand[0] + 2 * operand[1] + 1),
                             (uint8_t)operand[2]) != 0) {
            return VM_ERROR;
        }
        return VM_OK;
    case 2:                     /* storeb */
        return story_mem_write8(ctx->memory,
            (uint16_t)(operand[0] + operand[1]), (uint8_t)operand[2]) == 0 ?
            VM_OK : VM_ERROR;
    case 3:                     /* put_prop */
        return prop_put(ctx->memory, ctx->object_table, (uint8_t)operand[0],
            (uint8_t)operand[1], operand[2]) == 0 ? VM_OK : VM_ERROR;
    case 4:                     /* sread: read a line into the text
                                 * buffer at operand[0] (byte 0 is its
                                 * max length, characters start at
                                 * byte 1, V3 has no length byte),
                                 * lowercase it, then tokenize it into
                                 * the parse buffer at operand[1]. No
                                 * store, no branch in V3. */
        {
            uint8_t max_length;
            char buffer[256];
            int read_length;
            int i;

            if (ctx->read_line == 0 ||
                story_mem_read8(ctx->memory, operand[0], &max_length) != 0 ||
                max_length == 0) {
                return VM_ERROR;
            }
            read_length = ctx->read_line(buffer, max_length,
                                         ctx->read_line_context);
            if (read_length < 0 || read_length > max_length) {
                return VM_ERROR;
            }
            for (i = 0; i < read_length; ++i) {
                char c = buffer[i];

                if (c >= 'A' && c <= 'Z') {
                    c = (char)(c - 'A' + 'a');
                }
                if (story_mem_write8(ctx->memory,
                                     (uint16_t)(operand[0] + 1 + i),
                                     (uint8_t)c) != 0) {
                    return VM_ERROR;
                }
            }
            if (story_mem_write8(ctx->memory,
                                 (uint16_t)(operand[0] + 1 + read_length),
                                 0) != 0) {
                return VM_ERROR;
            }
            return parser_tokenize(ctx->memory, ctx->dictionary_table,
                (uint16_t)(operand[0] + 1), (uint8_t)read_length, 1,
                operand[1]) == 0 ? VM_OK : VM_ERROR;
        }
    case 5:                     /* print_char */
        return vm_emit(ctx, (char)operand[0]) == 0 ? VM_OK : VM_ERROR;
    case 6:                     /* print_num */
        return emit_decimal(ctx, (int16_t)operand[0]);
    case 7:                     /* random */
        return store_result(ctx, instr->store_variable,
            vm_random(ctx->state, (int16_t)operand[0]));
    case 8:                     /* push */
        return vm_push(ctx->state, operand[0]) == 0 ? VM_OK : VM_ERROR;
    case 9:                     /* pull: operand[0] is a variable
                                 * NUMBER, written indirectly */
        {
            uint16_t value;

            if (vm_pop(ctx->state, &value) != 0) {
                return VM_ERROR;
            }
            return vm_write_variable_indirect(ctx->state, ctx->memory,
                (uint8_t)operand[0], value) == 0 ? VM_OK : VM_ERROR;
        }
    case 19:                    /* output_stream: only streams 1
                                 * (screen, via ctx->emit) and 3
                                 * (memory table, via vm_emit) are
                                 * modeled -- 2/4 (transcript/the V6
                                 * command stream) are accepted as
                                 * no-ops, since this model has no
                                 * separate transcript sink */
        {
            int16_t number = (int16_t)operand[0];

            if (number == 3) {
                if (ctx->output_table_active ||
                    instr->operand_count < 2) {
                    return VM_ERROR;
                }
                ctx->output_table = operand[1];
                ctx->output_table_count = 0;
                ctx->output_table_active = 1;
            } else if (number == -3) {
                if (!ctx->output_table_active) {
                    return VM_ERROR;
                }
                if (story_mem_write8(ctx->memory, ctx->output_table,
                        (uint8_t)(ctx->output_table_count >> 8)) != 0 ||
                    story_mem_write8(ctx->memory,
                        (uint16_t)(ctx->output_table + 1),
                        (uint8_t)ctx->output_table_count) != 0) {
                    return VM_ERROR;
                }
                ctx->output_table_active = 0;
            }
            return VM_OK;
        }
    case 20:                    /* input_stream: only one input source
                                 * exists in this model (ctx->read_line);
                                 * accepted and ignored */
        return VM_OK;
    default:
        return VM_ERROR;
    }
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

    switch (instr.category) {
    case CATEGORY_2OP: return step_2op(ctx, &instr, operand);
    case CATEGORY_1OP: return step_1op(ctx, &instr, operand);
    case CATEGORY_0OP: return step_0op(ctx, &instr);
    case CATEGORY_VAR: return step_var(ctx, &instr, operand, next_pc);
    }
    return VM_ERROR;
}
