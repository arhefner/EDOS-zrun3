#include "ztext.h"

static const char alphabet[] = "abcdefghijklmnopqrstuvwxyz";

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