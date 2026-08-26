#ifndef ZRUN3_DICTIONARY_H
#define ZRUN3_DICTIONARY_H

#include <stddef.h>
#include <stdint.h>

#include "story_mem.h"

struct dict_header {
    uint16_t entries_addr;      /* address of the first entry */
    uint8_t entry_length;       /* bytes per entry (>= 4) */
    int16_t entry_count;        /* signed; negative means unsorted */
};

int dict_parse_header(const struct story_mem *memory, uint16_t dict_addr,
                      struct dict_header *header);

/* `encoded` is 4 bytes, e.g. from ztext_encode. *entry_addr is 0 if no
 * entry matches. A linear scan works for either sort order the header
 * declares; if entry_count is ever large enough for this to matter,
 * that's the place to add a binary-search fast path for the sorted
 * case, not here. */
int dict_lookup(const struct story_mem *memory,
                const struct dict_header *header, const uint8_t encoded[4],
                uint16_t *entry_addr);

/* Combines ztext_encode and dict_lookup for a plain ASCII word -- the
 * entry point most callers actually want. */
int dict_find_word(const struct story_mem *memory, uint16_t dict_addr,
                   const char *text, size_t length, uint16_t *entry_addr);

#endif
