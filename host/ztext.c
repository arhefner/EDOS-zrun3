#include "ztext.h"

static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz";
static const char alphabet_a1[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
/* Matches lib/zdec.asm's own zdec_a2 table exactly. Index 0 is z-char
 * 6's 10-bit ZSCII escape slot (unimplemented here, held by a space);
 * index 1 is z-char 7, a newline. ztext_encode never matches either,
 * so it searches from index 2 -- ' ' always encodes as z-char 0, and a
 * newline can never appear inside a dictionary word.
 *
 * BUG FIX: the newline at index 1 used to be missing here and in
 * lib/zdec.asm alike, shifting every digit and punctuation mark one
 * z-char early in decoded story text. Because this model carried the
 * identical error, the host tests agreed with the 1802 port and neither
 * caught it. */
static const char alphabet_a2[] = " \n0123456789.,!?_#'\"/\\-:()";

/* One in-flight z-char stream's cursor state -- factored out so the
 * exact same "pull the next z-char, refilling from a new word as
 * needed" logic can drive both the outer text being decoded and (for
 * exactly one nesting level) an abbreviation's own text, without
 * duplicating the word/end-of-string bookkeeping in two places. */
struct zchar_stream {
    const uint8_t *packed;
    uint16_t offset;
    uint16_t length;
    uint16_t word;
    unsigned pos;           /* 0-2: next z-char slot in `word`; 3:
                             * need to fetch a new word */
    int end_of_word;        /* current word's own end-of-string bit */
    int done;               /* true once a real terminator has been
                             * consumed, or the stream ran out early */
};

static void zchar_stream_init(struct zchar_stream *stream,
                              const uint8_t *packed, uint16_t length)
{
    stream->packed = packed;
    stream->offset = 0;
    stream->length = length;
    stream->word = 0;
    stream->pos = 3;
    stream->end_of_word = 0;
    stream->done = 0;
}

/* Returns 0 and *zchar = the next z-char (0-31), or -1 if the stream
 * has no more (a clean end, not an error -- the caller decides what
 * that means). Applies the standard "z-char 5 in the last slot of the
 * end-of-string word is padding, not a real character" rule. */
static int zchar_stream_next(struct zchar_stream *stream, unsigned *zchar)
{
    unsigned value;

    if (stream->pos == 3) {
        if (stream->done || stream->offset >= stream->length) {
            stream->done = 1;
            return -1;
        }
        stream->word = (uint16_t)(((uint16_t)stream->packed[stream->offset] << 8) |
                                  stream->packed[stream->offset + 1]);
        stream->offset = (uint16_t)(stream->offset + 2);
        stream->end_of_word = (stream->word & 0x8000u) != 0;
        stream->pos = 0;
    }

    value = (stream->pos == 0) ? ((stream->word >> 10) & 0x1fu) :
           (stream->pos == 1) ? ((stream->word >> 5) & 0x1fu) :
                                (stream->word & 0x1fu);

    /* BUG FIX: there used to be a "z-char 5 in the final word's third
     * slot means padding, so stop here" rule at this point. The
     * Z-machine standard has no such marker -- a string ends once every
     * z-char of the word with bit 15 set has been consumed, and the 5s
     * used to pad a short string are ordinary shift-to-A2 z-chars that
     * simply produce no output. The rule agreed with that for real
     * padding but swallowed a legitimate final z-char of 5, most
     * visibly the INDEX of a trailing abbreviation reference (ZORK I's
     * Kitchen description ends with abbreviation 5, "is "). lib/zdec.asm
     * mirrored this exactly, so the host tests and the 1802 port were
     * wrong together. */

    stream->pos += 1;
    if (stream->pos == 3 && stream->end_of_word) {
        stream->done = 1;
    }
    *zchar = value;
    return 0;
}

static int ztext_decode_stream(struct zchar_stream *stream,
                               ztext_emit_fn emit, void *context,
                               const uint8_t *image, size_t image_length,
                               uint16_t abbrev_table, int allow_abbrev)
{
    unsigned alphabet_set = 0;

    for (;;) {
        unsigned zchar;

        if (zchar_stream_next(stream, &zchar) != 0) {
            return 0;                  /* clean end of stream */
        }

        if (zchar == 0) {
            if (emit(' ', context) != 0) return -1;
        } else if (zchar == 4) {
            alphabet_set = 1;
        } else if (zchar == 5) {
            alphabet_set = 2;
        } else if (zchar >= 1 && zchar <= 3) {
            unsigned next_zc;
            uint16_t index;
            uint16_t entry_addr;
            uint16_t word_addr;
            uint16_t target_addr;
            uint16_t target_len;
            struct zchar_stream abbrev_stream;

            /* An abbreviation string may not itself reference another
             * abbreviation (Z-machine standard) -- reject rather than
             * expand a second level. */
            if (!allow_abbrev) {
                return -1;
            }
            /* The byte immediately following the marker is always a
             * real index value, never "trailing padding" -- deliberately
             * NOT going through the padding-detecting zchar_stream_next
             * for this specific peek would be wrong the other way
             * around (it already isn't: zchar_stream_next only treats
             * z-char 5 as padding, and only in an end-of-word's own
             * last slot; an index byte that happens to be 5 there is
             * still returned as data by the same function, so reusing
             * it here is correct, not a landmine). */
            if (zchar_stream_next(stream, &next_zc) != 0) {
                return -1;              /* marker with nothing following */
            }

            index = (uint16_t)(32u * (zchar - 1) + next_zc);
            entry_addr = (uint16_t)(abbrev_table + 2u * index);
            if ((size_t)entry_addr + 1 >= image_length) {
                return -1;
            }
            word_addr = (uint16_t)(((uint16_t)image[entry_addr] << 8) |
                                   image[entry_addr + 1]);
            target_addr = (uint16_t)(word_addr * 2u);
            if ((size_t)target_addr > image_length) {
                return -1;
            }
            /* No prior length measurement for an abbreviation's own
             * text either -- same generous-bound-then-let-the-real-
             * terminator-stop-it approach as print_addr/print_paddr
             * (see dispatch.c's own print_ztext_at). */
            target_len = (uint16_t)((image_length - target_addr) & ~1u);
            zchar_stream_init(&abbrev_stream, image + target_addr, target_len);
            if (ztext_decode_stream(&abbrev_stream, emit, context, image,
                                    image_length, abbrev_table, 0) != 0) {
                return -1;
            }
            /* alphabet_set is untouched by the nested expansion -- it's
             * local to each stream's own decode, matching the fact
             * that a shift (z-char 4/5) and an abbreviation marker are
             * unrelated concepts; only a real letter (zchar >= 6)
             * clears it, exactly as before this file supported
             * abbreviations at all. */
        } else {
            const char *table = alphabet_set == 0 ? alphabet :
                                alphabet_set == 1 ? alphabet_a1 :
                                                    alphabet_a2;
            if (emit(table[zchar - 6], context) != 0) return -1;
            alphabet_set = 0;
        }
    }
}

int ztext_decode(const uint8_t *packed, uint16_t length,
                 ztext_emit_fn emit, void *context,
                 const uint8_t *image, size_t image_length,
                 uint16_t abbrev_table)
{
    struct zchar_stream stream;

    if (packed == 0 || emit == 0 || (length & 1u) != 0) {
        return -1;
    }
    zchar_stream_init(&stream, packed, length);
    return ztext_decode_stream(&stream, emit, context, image, image_length,
                               abbrev_table, 1);
}

static int find_char(const char *table, char target)
{
    int index;

    for (index = 0; table[index] != '\0'; ++index) {
        if (table[index] == target) {
            return index;
        }
    }
    return -1;
}

int ztext_encode(const char *text, size_t length, uint8_t *packed)
{
    unsigned zchars[6] = {5, 5, 5, 5, 5, 5};
    unsigned zchar_count = 0;
    size_t index;
    uint16_t word0;
    uint16_t word1;

    if (text == 0 || packed == 0) {
        return -1;
    }
    for (index = 0; index < length && zchar_count < 6; ++index) {
        char c = text[index];
        int pos;
        unsigned shift = 0;
        unsigned code;
        unsigned needed;

        if (c == ' ') {
            code = 0;
            needed = 1;
        } else if (c >= 'a' && c <= 'z') {
            code = 6 + (unsigned)(c - 'a');
            needed = 1;
        } else if ((pos = find_char(alphabet_a1, c)) >= 0) {
            shift = 4;
            code = 6 + (unsigned)pos;
            needed = 2;
        } else if ((pos = find_char(alphabet_a2 + 2, c)) >= 0) {
            shift = 5;
            code = 6 + 2 + (unsigned)pos;
            needed = 2;
        } else {
            return -1;
        }
        if (zchar_count + needed > 6) {
            break;                     /* out of room: truncate here */
        }
        if (shift != 0) {
            zchars[zchar_count++] = shift;
        }
        zchars[zchar_count++] = code;
    }
    word0 = (uint16_t)((zchars[0] << 10) | (zchars[1] << 5) | zchars[2]);
    word1 = (uint16_t)(0x8000u | (zchars[3] << 10) | (zchars[4] << 5) |
                       zchars[5]);
    packed[0] = (uint8_t)(word0 >> 8);
    packed[1] = (uint8_t)word0;
    packed[2] = (uint8_t)(word1 >> 8);
    packed[3] = (uint8_t)word1;
    return 0;
}