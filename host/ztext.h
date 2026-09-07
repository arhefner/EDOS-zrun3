#ifndef ZRUN3_ZTEXT_H
#define ZRUN3_ZTEXT_H

#include <stddef.h>
#include <stdint.h>

typedef int (*ztext_emit_fn)(char character, void *context);

/* `image`/`image_length` are the whole story file (guest address 0
 * through length), and `abbrev_table` is the header's own abbreviations
 * field -- needed only to expand a z-char 1-3 abbreviation reference
 * (looked up as a word at image[abbrev_table + 2*index], itself a
 * packed address, i.e. that word's own value * 2). An abbreviation's
 * own text may not reference a further abbreviation (per the Z-machine
 * standard); a violation of that returns -1, not a second expansion. */
int ztext_decode(const uint8_t *packed, uint16_t length,
                 ztext_emit_fn emit, void *context,
                 const uint8_t *image, size_t image_length,
                 uint16_t abbrev_table);

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