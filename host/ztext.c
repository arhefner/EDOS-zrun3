#include "ztext.h"

static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz";
static const char alphabet_a1[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
/* Matches ztext_decode's own A2 table exactly, including its unused
 * leading space (index 0) -- ztext_encode never matches a character
 * there, since ' ' always encodes as z-char 0 instead. */
static const char alphabet_a2[] = " 0123456789.,!?_#'\"/\\-:()";

int ztext_decode(const uint8_t *packed, uint16_t length,
                 ztext_emit_fn emit, void *context)
{
    uint16_t offset = 0;
    unsigned alphabet_set = 0;
    unsigned shift_once = 0;

    if (packed == 0 || emit == 0 || (length & 1u) != 0) {
        return -1;
    }
    while (offset < length) {
        uint16_t word = (uint16_t)(((uint16_t)packed[offset] << 8) |
                                   packed[offset + 1]);
        int end_word = (word & 0x8000u) != 0;
        unsigned zchars[3] = {
            (unsigned)((word >> 10) & 0x1f),
            (unsigned)((word >> 5) & 0x1f),
            (unsigned)(word & 0x1f)
        };
        unsigned index;
        offset += 2;
        for (index = 0; index < 3; ++index) {
            unsigned zchar = zchars[index];
            if (end_word && zchar == 5 && index == 2) {
                break;
            }
            if (zchar == 0) {
                if (emit(' ', context) != 0) return -1;
            } else if (zchar >= 6) {
                const char *table = alphabet_set == 0 ? alphabet :
                                    alphabet_set == 1 ? "ABCDEFGHIJKLMNOPQRSTUVWXYZ" :
                                    " 0123456789.,!?_#'\"/\\-:()";
                if (zchar - 6 >= 26 && alphabet_set < 2) return -1;
                if (emit(table[zchar - 6], context) != 0) return -1;
                alphabet_set = 0;
            } else if (zchar == 4) {
                alphabet_set = 1;
                shift_once = 1;
            } else if (zchar == 5) {
                alphabet_set = 2;
                shift_once = 1;
            } else {
                return -1;
            }
            if (shift_once && zchar >= 6) {
                alphabet_set = 0;
                shift_once = 0;
            }
        }
        if (end_word) {
            break;
        }
    }
    return 0;
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
        } else if ((pos = find_char(alphabet_a2 + 1, c)) >= 0) {
            shift = 5;
            code = 6 + 1 + (unsigned)pos;
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