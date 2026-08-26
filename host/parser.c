#include "parser.h"

#include "dictionary.h"

enum { PARSER_OK = 0, PARSER_ERROR = -1 };

static int is_separator(const struct story_mem *memory, uint16_t dict_addr,
                        uint8_t c, int *is_sep)
{
    uint8_t separator_count;
    uint8_t index;

    if (story_mem_read8(memory, dict_addr, &separator_count) != 0) {
        return PARSER_ERROR;
    }
    for (index = 0; index < separator_count; ++index) {
        uint8_t separator;

        if (story_mem_read8(memory, (uint16_t)(dict_addr + 1 + index),
                            &separator) != 0) {
            return PARSER_ERROR;
        }
        if (separator == c) {
            *is_sep = 1;
            return PARSER_OK;
        }
    }
    *is_sep = 0;
    return PARSER_OK;
}

int parser_tokenize(struct story_mem *memory, uint16_t dict_addr,
                    uint16_t text_addr, uint8_t text_length,
                    uint8_t text_offset, uint16_t parse_addr)
{
    uint8_t max_words;
    uint8_t word_count;
    uint16_t pos;
    uint16_t parse_cursor;

    if (memory == 0 ||
        story_mem_read8(memory, parse_addr, &max_words) != 0) {
        return PARSER_ERROR;
    }
    parse_cursor = (uint16_t)(parse_addr + 2);
    word_count = 0;
    pos = 0;

    while (pos < text_length && word_count < max_words) {
        uint8_t c;
        int sep;
        uint16_t start;
        uint8_t length;
        char word_buf[6];
        uint8_t read_len;
        uint8_t i;
        uint16_t entry_addr;

        if (story_mem_read8(memory, (uint16_t)(text_addr + pos), &c) != 0) {
            return PARSER_ERROR;
        }
        if (c == ' ') {
            ++pos;
            continue;
        }
        if (is_separator(memory, dict_addr, c, &sep) != PARSER_OK) {
            return PARSER_ERROR;
        }
        start = pos;
        if (sep) {
            length = 1;
            ++pos;
        } else {
            length = 0;
            while (pos < text_length) {
                if (story_mem_read8(memory, (uint16_t)(text_addr + pos),
                                    &c) != 0) {
                    return PARSER_ERROR;
                }
                if (c == ' ') {
                    break;
                }
                if (is_separator(memory, dict_addr, c, &sep) != PARSER_OK) {
                    return PARSER_ERROR;
                }
                if (sep) {
                    break;
                }
                ++pos;
                ++length;
            }
        }

        read_len = length > 6 ? 6 : length;
        for (i = 0; i < read_len; ++i) {
            uint8_t ch;

            if (story_mem_read8(memory, (uint16_t)(text_addr + start + i),
                                &ch) != 0) {
                return PARSER_ERROR;
            }
            word_buf[i] = (char)ch;
        }
        if (dict_find_word(memory, dict_addr, word_buf, read_len,
                           &entry_addr) != 0) {
            return PARSER_ERROR;
        }

        if (story_mem_write8(memory, parse_cursor,
                             (uint8_t)(entry_addr >> 8)) != 0 ||
            story_mem_write8(memory, (uint16_t)(parse_cursor + 1),
                             (uint8_t)entry_addr) != 0 ||
            story_mem_write8(memory, (uint16_t)(parse_cursor + 2),
                             length) != 0 ||
            story_mem_write8(memory, (uint16_t)(parse_cursor + 3),
                             (uint8_t)(text_offset + start)) != 0) {
            return PARSER_ERROR;
        }
        parse_cursor = (uint16_t)(parse_cursor + 4);
        ++word_count;
    }

    if (story_mem_write8(memory, (uint16_t)(parse_addr + 1), word_count) !=
        0) {
        return PARSER_ERROR;
    }
    return PARSER_OK;
}
