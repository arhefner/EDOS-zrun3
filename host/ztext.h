#ifndef ZRUN3_ZTEXT_H
#define ZRUN3_ZTEXT_H

#include <stddef.h>
#include <stdint.h>

typedef int (*ztext_emit_fn)(char character, void *context);

int ztext_decode(const uint8_t *packed, uint16_t length,
                 ztext_emit_fn emit, void *context);

/* A V3 dictionary word is always 6 z-characters (2 z-words, 4 bytes),
 * padded with the shift-to-A2 filler character if `text` is shorter
 * and truncated (at a z-character boundary, not a byte boundary --
 * see ztext_encode's own comment) if longer. */
#define ZTEXT_V3_ENCODED_LENGTH 4

/* Encodes up to a dictionary word's worth of lowercase/uppercase
 * ASCII letters, digits, and the standard A2 punctuation set into
 * packed[0..ZTEXT_V3_ENCODED_LENGTH-1], ready to compare byte-for-byte
 * against a V3 dictionary entry. Returns -1 only for a character that
 * can't be encoded at all (not -1 for a word that's simply too long
 * to fit -- that's truncated, matching how a real Z-machine dictionary
 * treats overlong player input).
 */
int ztext_encode(const char *text, size_t length, uint8_t *packed);

#endif