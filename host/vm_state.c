#include "vm_state.h"

#include <string.h>
#include <time.h>

void vm_state_init(struct vm_state *state, uint16_t globals_base,
                   uint16_t initial_pc)
{
    memset(state, 0, sizeof(*state));
    state->globals_base = globals_base;
    state->pc = initial_pc;
    state->random_state = 0x2545f491u;
}

int vm_push(struct vm_state *state, uint16_t value)
{
    if (state == 0 || state->eval_depth >= VM_EVAL_STACK_MAX) {
        return -1;
    }
    state->eval_stack[state->eval_depth++] = value;
    return 0;
}

int vm_pop(struct vm_state *state, uint16_t *value)
{
    if (state == 0 || value == 0 || state->eval_depth == 0) {
        return -1;
    }
    *value = state->eval_stack[--state->eval_depth];
    return 0;
}

int vm_frame_push(struct vm_state *state, uint16_t return_pc,
                  uint8_t store_variable, uint8_t argument_count,
                  const uint16_t *locals, uint8_t local_count)
{
    struct vm_frame *frame;

    if (state == 0 || local_count > VM_LOCALS_MAX ||
        state->frame_depth >= VM_FRAMES_MAX ||
        (local_count != 0 && locals == 0)) {
        return -1;
    }
    frame = &state->frames[state->frame_depth++];
    memset(frame, 0, sizeof(*frame));
    frame->return_pc = return_pc;
    frame->store_variable = store_variable;
    frame->argument_count = argument_count;
    frame->local_count = local_count;
    frame->stack_base = state->eval_depth;
    if (local_count != 0) {
        memcpy(frame->locals, locals, local_count * sizeof(locals[0]));
    }
    return 0;
}

int vm_frame_pop(struct vm_state *state, struct vm_frame *frame)
{
    if (state == 0 || frame == 0 || state->frame_depth == 0) {
        return -1;
    }
    *frame = state->frames[--state->frame_depth];
    if (state->eval_depth > frame->stack_base) {
        state->eval_depth = frame->stack_base;
    }
    return 0;
}

static int vm_current_frame(struct vm_state *state, struct vm_frame **frame)
{
    if (state == 0 || state->frame_depth == 0) {
        return -1;
    }
    *frame = &state->frames[state->frame_depth - 1];
    return 0;
}

int vm_read_variable(struct vm_state *state, const struct story_mem *memory,
                     uint8_t variable, uint16_t *value)
{
    struct vm_frame *frame;

    if (state == 0 || memory == 0 || value == 0) {
        return -1;
    }
    if (variable == 0) {
        return vm_pop(state, value);
    }
    if (variable < 16) {
        if (vm_current_frame(state, &frame) != 0 ||
            variable > frame->local_count) {
            return -1;
        }
        *value = frame->locals[variable - 1];
        return 0;
    }
    return story_mem_read16(memory,
        (uint16_t)(state->globals_base + (variable - 16) * 2), value);
}

int vm_write_variable(struct vm_state *state, struct story_mem *memory,
                      uint8_t variable, uint16_t value)
{
    struct vm_frame *frame;
    uint16_t addr;

    if (state == 0 || memory == 0) {
        return -1;
    }
    if (variable == 0) {
        return vm_push(state, value);
    }
    if (variable < 16) {
        if (vm_current_frame(state, &frame) != 0 ||
            variable > frame->local_count) {
            return -1;
        }
        frame->locals[variable - 1] = value;
        return 0;
    }
    addr = (uint16_t)(state->globals_base + (variable - 16) * 2);
    if (story_mem_write8(memory, addr, (uint8_t)(value >> 8)) != 0 ||
        story_mem_write8(memory, (uint16_t)(addr + 1), (uint8_t)value) != 0) {
        return -1;
    }
    return 0;
}

int vm_read_variable_indirect(struct vm_state *state,
                              const struct story_mem *memory,
                              uint8_t variable, uint16_t *value)
{
    if (state == 0 || value == 0) {
        return -1;
    }
    if (variable == 0) {
        if (state->eval_depth == 0) {
            return -1;
        }
        *value = state->eval_stack[state->eval_depth - 1];
        return 0;
    }
    return vm_read_variable(state, memory, variable, value);
}

int vm_write_variable_indirect(struct vm_state *state,
                               struct story_mem *memory,
                               uint8_t variable, uint16_t value)
{
    if (state == 0) {
        return -1;
    }
    if (variable == 0) {
        if (state->eval_depth == 0) {
            return -1;
        }
        state->eval_stack[state->eval_depth - 1] = value;
        return 0;
    }
    return vm_write_variable(state, memory, variable, value);
}

static uint32_t xorshift32(uint32_t *state)
{
    uint32_t x = *state;

    x ^= x << 13;
    x ^= x >> 17;
    x ^= x << 5;
    *state = x;
    return x;
}

uint16_t vm_random(struct vm_state *state, int16_t range)
{
    if (range > 0) {
        return (uint16_t)(1 + xorshift32(&state->random_state) %
                          (uint32_t)range);
    }
    if (range == 0) {
        state->random_state = (uint32_t)time(0) | 1u;  /* xorshift32 never
                                                         * advances from an
                                                         * all-zero state */
    } else {
        state->random_state = (uint32_t)(-(int32_t)range) | 1u;
    }
    return 0;
}