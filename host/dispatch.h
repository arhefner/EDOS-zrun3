#ifndef ZRUN3_DISPATCH_H
#define ZRUN3_DISPATCH_H

#include <stdint.h>

#include "story_mem.h"
#include "vm_state.h"
#include "ztext.h"

struct vm_context {
    struct story_mem *memory;
    struct vm_state *state;
    uint16_t object_table;      /* from the story header; needed by
                                * every object/property opcode */
    ztext_emit_fn emit;         /* called for each character a "print"-
                                * family or new_line opcode produces */
    void *emit_context;
    int quit;                   /* set to 1 by the "quit" opcode */
};

/* Executes exactly one instruction at state->pc, advancing pc (or
 * branching/calling/returning as the opcode itself dictates). Still
 * not the full V3 instruction set (missing: save/restore/restart,
 * scoring/status-line opcodes, sread/the parser opcodes, random, and
 * output/input stream control), but covers arithmetic, comparison,
 * variables, memory (loadw/storew/loadb/storeb), the object tree,
 * properties, and every text-producing opcode. Returns -1 for a
 * decode error or any other opcode -- dispatch simply doesn't
 * recognize it yet. */
int vm_step(struct vm_context *ctx);

#endif
