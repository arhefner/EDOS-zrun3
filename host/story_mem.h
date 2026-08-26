#ifndef ZRUN3_STORY_MEM_H
#define ZRUN3_STORY_MEM_H

#include <stddef.h>
#include <stdint.h>

struct story_mem {
    uint8_t *image;
    size_t length;
    uint16_t dynamic_end;
};

int story_mem_init(struct story_mem *memory, uint8_t *image, size_t length,
                   uint16_t dynamic_end);
int story_mem_read8(const struct story_mem *memory, uint16_t address,
                    uint8_t *value);
int story_mem_read16(const struct story_mem *memory, uint16_t address,
                     uint16_t *value);
int story_mem_write8(struct story_mem *memory, uint16_t address, uint8_t value);

#endif