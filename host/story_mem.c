#include "story_mem.h"

enum { STORY_MEM_OK = 0, STORY_MEM_ERROR = -1 };

int story_mem_init(struct story_mem *memory, uint8_t *image, size_t length,
                   uint16_t dynamic_end)
{
    if (memory == 0 || image == 0 || length > UINT16_MAX + 1u ||
        dynamic_end > length) {
        return STORY_MEM_ERROR;
    }
    memory->image = image;
    memory->length = length;
    memory->dynamic_end = dynamic_end;
    return STORY_MEM_OK;
}

int story_mem_read8(const struct story_mem *memory, uint16_t address,
                    uint8_t *value)
{
    if (memory == 0 || value == 0 || address >= memory->length) {
        return STORY_MEM_ERROR;
    }
    *value = memory->image[address];
    return STORY_MEM_OK;
}

int story_mem_read16(const struct story_mem *memory, uint16_t address,
                     uint16_t *value)
{
    uint8_t high;
    uint8_t low;

    if (value == 0 || story_mem_read8(memory, address, &high) != STORY_MEM_OK ||
        address == UINT16_MAX ||
        story_mem_read8(memory, (uint16_t)(address + 1), &low) != STORY_MEM_OK) {
        return STORY_MEM_ERROR;
    }
    *value = (uint16_t)(((uint16_t)high << 8) | low);
    return STORY_MEM_OK;
}

int story_mem_write8(struct story_mem *memory, uint16_t address, uint8_t value)
{
    if (memory == 0 || address >= memory->dynamic_end) {
        return STORY_MEM_ERROR;
    }
    memory->image[address] = value;
    return STORY_MEM_OK;
}