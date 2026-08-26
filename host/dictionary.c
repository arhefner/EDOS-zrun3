#include "dictionary.h"

#include "ztext.h"

enum { DICT_OK = 0, DICT_ERROR = -1 };

int dict_parse_header(const struct story_mem *memory, uint16_t dict_addr,
                      struct dict_header *header)
{
    uint8_t separator_count;
    uint8_t entry_length;
    uint16_t entry_length_addr;
    uint16_t count_raw;

    if (memory == 0 || header == 0 ||
        story_mem_read8(memory, dict_addr, &separator_count) != 0) {
        return DICT_ERROR;
    }
    entry_length_addr = (uint16_t)(dict_addr + 1 + separator_count);
    if (story_mem_read8(memory, entry_length_addr, &entry_length) != 0 ||
        entry_length < ZTEXT_V3_ENCODED_LENGTH ||
        story_mem_read16(memory, (uint16_t)(entry_length_addr + 1),
                         &count_raw) != 0) {
        return DICT_ERROR;
    }
    header->entry_length = entry_length;
    header->entry_count = (int16_t)count_raw;
    header->entries_addr = (uint16_t)(entry_length_addr + 3);
    return DICT_OK;
}

int dict_lookup(const struct story_mem *memory,
                const struct dict_header *header, const uint8_t encoded[4],
                uint16_t *entry_addr)
{
    int16_t count;
    int16_t index;
    uint16_t addr;

    if (memory == 0 || header == 0 || encoded == 0 || entry_addr == 0) {
        return DICT_ERROR;
    }
    count = header->entry_count < 0 ? (int16_t)-header->entry_count :
                                      header->entry_count;
    addr = header->entries_addr;
    for (index = 0; index < count; ++index) {
        uint8_t byte;
        int match = 1;
        int i;

        for (i = 0; i < ZTEXT_V3_ENCODED_LENGTH; ++i) {
            if (story_mem_read8(memory, (uint16_t)(addr + i), &byte) != 0) {
                return DICT_ERROR;
            }
            if (byte != encoded[i]) {
                match = 0;
            }
        }
        if (match) {
            *entry_addr = addr;
            return DICT_OK;
        }
        addr = (uint16_t)(addr + header->entry_length);
    }
    *entry_addr = 0;
    return DICT_OK;
}

int dict_find_word(const struct story_mem *memory, uint16_t dict_addr,
                   const char *text, size_t length, uint16_t *entry_addr)
{
    struct dict_header header;
    uint8_t encoded[ZTEXT_V3_ENCODED_LENGTH];

    if (ztext_encode(text, length, encoded) != 0 ||
        dict_parse_header(memory, dict_addr, &header) != DICT_OK) {
        return DICT_ERROR;
    }
    return dict_lookup(memory, &header, encoded, entry_addr);
}
