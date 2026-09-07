#include "story_header.h"

enum { STORY_HEADER_SIZE = 64, STORY_HEADER_ERROR = -1 };

static uint16_t read_word(const uint8_t *image, size_t offset)
{
    return (uint16_t)(((uint16_t)image[offset] << 8) | image[offset + 1]);
}

int story_header_parse(const uint8_t *image, size_t length,
                       struct story_header *header)
{
    size_t index;
    uint32_t declared_length;

    if (image == 0 || header == 0 || length < STORY_HEADER_SIZE ||
        image[0] != 3) {
        return STORY_HEADER_ERROR;
    }
    header->version = image[0];
    header->release = read_word(image, 2);
    header->high_memory = read_word(image, 4);
    header->initial_pc = read_word(image, 6);
    header->dictionary = read_word(image, 8);
    header->object_table = read_word(image, 10);
    header->globals = read_word(image, 12);
    header->static_memory = read_word(image, 14);
    header->abbreviations = read_word(image, 24);
    header->file_length = (uint32_t)read_word(image, 26) * 2u;
    header->checksum = read_word(image, 28);
    for (index = 0; index < 6; ++index) {
        header->serial[index] = (char)image[18 + index];
    }
    header->serial[6] = '\0';

    declared_length = header->file_length;
    if (declared_length < STORY_HEADER_SIZE || declared_length > length ||
        header->high_memory < header->static_memory ||
        header->static_memory < STORY_HEADER_SIZE ||
        header->object_table >= header->static_memory ||
        header->globals < 0x0c || header->globals >= header->static_memory ||
        header->abbreviations >= header->static_memory) {
        return STORY_HEADER_ERROR;
    }
    return 0;
}