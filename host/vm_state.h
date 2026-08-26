#ifndef ZRUN3_VM_STATE_H
#define ZRUN3_VM_STATE_H

#include <stdint.h>

#define VM_EVAL_STACK_MAX 1024
#define VM_LOCALS_MAX 15
#define VM_FRAMES_MAX 64

struct vm_frame {
    uint16_t return_pc;
    uint8_t store_variable;
    uint8_t argument_count;
    uint8_t local_count;
    uint16_t locals[VM_LOCALS_MAX];
    uint16_t stack_base;
};

struct vm_state {
    uint16_t pc;
    uint16_t globals_base;
    uint16_t globals[240];
    uint16_t eval_stack[VM_EVAL_STACK_MAX];
    uint16_t eval_depth;
    struct vm_frame frames[VM_FRAMES_MAX];
    uint16_t frame_depth;
};

void vm_state_init(struct vm_state *state, uint16_t globals_base,
                   uint16_t initial_pc);
int vm_push(struct vm_state *state, uint16_t value);
int vm_pop(struct vm_state *state, uint16_t *value);
int vm_frame_push(struct vm_state *state, uint16_t return_pc,
                  uint8_t store_variable, uint8_t argument_count,
                  const uint16_t *locals, uint8_t local_count);
int vm_frame_pop(struct vm_state *state, struct vm_frame *frame);

#endif