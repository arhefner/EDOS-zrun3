#ifndef ZRUN3_PARSER_H
#define ZRUN3_PARSER_H

#include <stdint.h>

#include "story_mem.h"

/* Tokenizes the ASCII text at text_addr (text_length bytes, already
 * lowercase, no header) against the dictionary at dict_addr, writing
 * up to parse_addr[0] (already there, read not written) word records
 * into the parse buffer at parse_addr in the standard V3 format:
 * parse_addr[1] = word count (written here), then 4 bytes per word --
 * dictionary entry address (0 if the word isn't listed, not an
 * error), length, and position. Splits on spaces and the dictionary's
 * own separator characters; each separator other than space is also
 * a one-character word in its own right, per the Z-machine standard.
 *
 * `text_offset` is added to each word's position before it's written
 * (2 for a real text buffer, whose characters start right after its
 * 2-byte header) -- callers own scanning their own version's text
 * buffer format (V3's zero-terminated bytes here) for text_length;
 * this function only tokenizes what it's given. */
int parser_tokenize(struct story_mem *memory, uint16_t dict_addr,
                    uint16_t text_addr, uint8_t text_length,
                    uint8_t text_offset, uint16_t parse_addr);

#endif
