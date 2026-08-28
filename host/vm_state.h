#ifndef ZRUN3_VM_STATE_H
#define ZRUN3_VM_STATE_H

#include <stdint.h>

#include "story_mem.h"

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
    uint16_t globals_base;      /* global variables live in story memory
                                 * at globals_base + (var-16)*2, per
                                 * ARCHITECTURE.md's "story bytes always
                                 * go through story_mem" rule -- there is
                                 * deliberately no separate in-VM copy */
    uint16_t eval_stack[VM_EVAL_STACK_MAX];
    uint16_t eval_depth;
    struct vm_frame frames[VM_FRAMES_MAX];
    uint16_t frame_depth;
    uint32_t random_state;      /* xorshift32 PRNG state for vm_random;
                                 * seeded to a fixed nonzero default by
                                 * vm_state_init so range>0 draws work
                                 * before the game ever reseeds */
};

void vm_state_init(struct vm_state *state, uint16_t globals_base,
                   uint16_t initial_pc);
int vm_push(struct vm_state *state, uint16_t value);
int vm_pop(struct vm_state *state, uint16_t *value);
int vm_frame_push(struct vm_state *state, uint16_t return_pc,
                  uint8_t store_variable, uint8_t argument_count,
                  const uint16_t *locals, uint8_t local_count);
int vm_frame_pop(struct vm_state *state, struct vm_frame *frame);

/* "Operand" access: reading variable 0 pops the stack, writing pushes
 * onto it. Use this whenever an operand's encoded type is "variable"
 * (i.e. its value comes FROM this variable) -- which is every operand
 * read in the instruction set except the variable-NUMBER operand of
 * store/load/inc/dec/inc_chk/dec_chk/pull, which use the indirect
 * functions below instead (Z-Machine Standard 6.3.4). Variables 1-15
 * are the current call frame's locals; 16-255 are globals, read/
 * written through `memory` at globals_base + (variable-16)*2. */
int vm_read_variable(struct vm_state *state, const struct story_mem *memory,
                     uint8_t variable, uint16_t *value);
int vm_write_variable(struct vm_state *state, struct story_mem *memory,
                      uint8_t variable, uint16_t value);

/* "Indirect" access: reading variable 0 peeks the top of the stack
 * without popping; writing replaces it in place without pushing. Only
 * for store/load/inc/dec/inc_chk/dec_chk/pull's own variable-number
 * operand -- everything else should use the functions above. */
int vm_read_variable_indirect(struct vm_state *state,
                              const struct story_mem *memory,
                              uint8_t variable, uint16_t *value);
int vm_write_variable_indirect(struct vm_state *state,
                               struct story_mem *memory,
                               uint8_t variable, uint16_t value);

/* Implements the "random" opcode's exact semantics: range > 0 returns
 * a uniform draw in [1, range]; range == 0 reseeds unpredictably (from
 * the wall clock) and returns 0; range < 0 reseeds to a value derived
 * from range itself, for a repeatable sequence useful in testing, and
 * also returns 0. */
uint16_t vm_random(struct vm_state *state, int16_t range);

#endif