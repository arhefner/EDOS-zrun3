#include "vm_state.h"

#include <string.h>

void vm_state_init(struct vm_state *state, uint16_t globals_base,
                   uint16_t initial_pc)
{
    memset(state, 0, sizeof(*state));
    state->globals_base = globals_base;
    state->pc = initial_pc;
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