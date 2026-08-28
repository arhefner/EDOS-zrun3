#ifndef ZRUN3_DISPATCH_H
#define ZRUN3_DISPATCH_H

#include <stdint.h>

#include "story_mem.h"
#include "vm_state.h"
#include "ztext.h"

/* Fetches one line of raw input for "sread" (echoing it is the
 * caller's job, same as a real terminal driver, not this callback's).
 * Returns the number of characters written to `buffer` (0 for an
 * empty line, never more than max_length, no trailing newline), or -1
 * on error/abort. */
typedef int (*vm_read_line_fn)(char *buffer, uint8_t max_length,
                               void *context);

/* "save"/"restore"/"restart" hand the platform layer a live pointer to
 * the interpreter's own state and dynamic-memory bytes rather than a
 * serialized blob -- how (or whether) to actually persist that data
 * is entirely the platform's problem; this reference model only needs
 * the opcodes' own control flow to be correct. vm_save_fn reads
 * `state`/`dynamic_memory`; vm_restore_fn (used for both restore and
 * restart) fills them in place. Both return 0 for success. */
typedef int (*vm_save_fn)(const struct vm_state *state,
                          const uint8_t *dynamic_memory,
                          uint16_t dynamic_length, void *context);
typedef int (*vm_restore_fn)(struct vm_state *state, uint8_t *dynamic_memory,
                             uint16_t dynamic_length, void *context);

struct vm_context {
    struct story_mem *memory;
    struct vm_state *state;
    uint16_t object_table;      /* from the story header; needed by
                                * every object/property opcode */
    uint16_t dictionary_table;  /* from the story header; needed by
                                * "sread" to tokenize against the
                                * game's own dictionary */
    ztext_emit_fn emit;         /* called for each character a "print"-
                                * family or new_line opcode produces,
                                * unless "output_stream" has redirected
                                * output into a memory table instead */
    void *emit_context;
    uint16_t output_table;      /* set by output_stream(3, table) */
    uint16_t output_table_count;
    int output_table_active;
    vm_read_line_fn read_line;  /* called by "sread"; may be 0 if the
                                * game never uses it */
    void *read_line_context;
    vm_save_fn save;            /* called by "save"; may be 0, which
                                * behaves as "save always fails" */
    void *save_context;
    vm_restore_fn restore;      /* called by "restore"; may be 0,
                                * which behaves as "restore always
                                * fails" */
    void *restore_context;
    vm_restore_fn restart;      /* called by "restart"; may be 0, in
                                * which case "restart" is a decode-
                                * recognized but unsupported opcode
                                * (returns an error) rather than
                                * silently doing nothing */
    void *restart_context;
    int quit;                   /* set to 1 by the "quit" opcode */
};

/* Executes exactly one instruction at state->pc, advancing pc (or
 * branching/calling/returning as the opcode itself dictates). Covers
 * the full V3 instruction set except "verify" (the story-file
 * checksum opcode -- this reference model has no notion of a story
 * file to checksum) and "call 0" (do_call's own documented gap):
 * arithmetic, comparison, variables, memory (loadw/storew/loadb/
 * storeb), the object tree, properties, every text-producing opcode,
 * random, sread (ties in the dictionary/parser subsystems), save/
 * restore/restart (via caller-supplied callbacks -- see vm_save_fn/
 * vm_restore_fn above), output_stream's memory-table redirection, and
 * the no-op stubs (input_stream, show_status) for opcodes whose real
 * behavior belongs to the platform layer, not this portable core.
 * Returns -1 for a decode error or any other opcode -- dispatch simply
 * doesn't recognize it yet. */
int vm_step(struct vm_context *ctx);

#endif
