#ifndef ZRUN3_DISPATCH_H
#define ZRUN3_DISPATCH_H

#include <stdint.h>

#include "story_mem.h"
#include "vm_state.h"
#include "ztext.h"

struct vm_context {
    struct story_mem *memory;
    struct vm_state *state;
    ztext_emit_fn emit;         /* called for each character a "print"
                                * or new_line opcode produces */
    void *emit_context;
    int quit;                   /* set to 1 by the "quit" opcode */
};

/* Executes exactly one instruction at state->pc, advancing pc (or
 * branching/calling/returning as the opcode itself dictates). This is
 * a proof-of-concept slice, not the full V3 instruction set: 2OP je/
 * store/add/sub, 1OP jz/ret/jump, 0OP rtrue/rfalse/print/new_line/
 * quit, and VAR call. Returns -1 for a decode error or any other
 * opcode -- dispatch simply doesn't recognize it yet. */
int vm_step(struct vm_context *ctx);

#endif
