#ifndef ZRUN3_STORY_HEADER_H
#define ZRUN3_STORY_HEADER_H

#include <stddef.h>
#include <stdint.h>

struct story_header {
    uint8_t version;
    uint16_t release;
    uint16_t high_memory;
    uint16_t initial_pc;
    uint16_t dictionary;
    uint16_t object_table;
    uint16_t globals;
    uint16_t static_memory;
    uint16_t abbreviations;
    uint32_t file_length;
    uint16_t checksum;
    char serial[7];
};

int story_header_parse(const uint8_t *image, size_t length,
                       struct story_header *header);

#endif