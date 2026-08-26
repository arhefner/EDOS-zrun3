#include "properties.h"

#include "objects.h"

enum { PROP_OK = 0, PROP_ERROR = -1 };

/* Reads one property-list entry at `addr`. On a real entry, sets the
 * number/data address/length outputs and *next to the address the
 * next entry would start at. On the list terminator (size byte 0),
 * sets *number to 0 and leaves the rest unset. */
static int prop_read_entry(const struct story_mem *memory, uint16_t addr,
                           uint8_t *number, uint16_t *data_addr, uint8_t *len,
                           uint16_t *next)
{
    uint8_t size_byte;

    if (story_mem_read8(memory, addr, &size_byte) != 0) {
        return PROP_ERROR;
    }
    if (size_byte == 0) {
        *number = 0;
        return PROP_OK;
    }
    *number = (uint8_t)(size_byte & 0x1f);
    *len = (uint8_t)((size_byte >> 5) + 1);
    *data_addr = (uint16_t)(addr + 1);
    *next = (uint16_t)(*data_addr + *len);
    return PROP_OK;
}

static int prop_list_start(const struct story_mem *memory,
                           uint16_t object_table, uint8_t object,
                           uint16_t *start)
{
    uint16_t name_addr;
    uint16_t name_len;

    if (obj_short_name(memory, object_table, object, &name_addr, &name_len) != 0) {
        return PROP_ERROR;
    }
    *start = (uint16_t)(name_addr + name_len);
    return PROP_OK;
}

int prop_get_addr(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t property, uint16_t *addr)
{
    uint16_t cursor;
    uint8_t number;
    uint16_t data_addr;
    uint8_t len;
    uint16_t next;

    if (addr == 0 || property == 0 || property > PROP_NUMBER_MAX ||
        prop_list_start(memory, object_table, object, &cursor) != PROP_OK) {
        return PROP_ERROR;
    }
    for (;;) {
        if (prop_read_entry(memory, cursor, &number, &data_addr, &len, &next) != PROP_OK) {
            return PROP_ERROR;
        }
        if (number == 0) {
            *addr = 0;
            return PROP_OK;
        }
        if (number == property) {
            *addr = data_addr;
            return PROP_OK;
        }
        cursor = next;
    }
}

int prop_get_len(const struct story_mem *memory, uint16_t addr, uint8_t *len)
{
    uint8_t size_byte;

    if (len == 0) {
        return PROP_ERROR;
    }
    if (addr == 0) {
        *len = 0;
        return PROP_OK;
    }
    if (story_mem_read8(memory, (uint16_t)(addr - 1), &size_byte) != 0) {
        return PROP_ERROR;
    }
    *len = (uint8_t)((size_byte >> 5) + 1);
    return PROP_OK;
}

int prop_get(const struct story_mem *memory, uint16_t object_table,
            uint8_t object, uint8_t property, uint16_t *value)
{
    uint16_t addr;
    uint8_t len;
    uint8_t byte;
    uint16_t word;

    if (value == 0 || property == 0 || property > PROP_NUMBER_MAX ||
        prop_get_addr(memory, object_table, object, property, &addr) != PROP_OK) {
        return PROP_ERROR;
    }
    if (addr == 0) {
        if (story_mem_read16(memory,
                             (uint16_t)(object_table + (property - 1) * 2),
                             value) != 0) {
            return PROP_ERROR;
        }
        return PROP_OK;
    }
    if (prop_get_len(memory, addr, &len) != PROP_OK) {
        return PROP_ERROR;
    }
    if (len == 1) {
        if (story_mem_read8(memory, addr, &byte) != 0) {
            return PROP_ERROR;
        }
        *value = byte;
        return PROP_OK;
    }
    if (story_mem_read16(memory, addr, &word) != 0) {
        return PROP_ERROR;
    }
    *value = word;
    return PROP_OK;
}

int prop_get_next(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t property, uint8_t *next_property)
{
    uint16_t cursor;
    uint8_t number;
    uint16_t data_addr;
    uint8_t len;
    uint16_t next;
    int want_first;

    if (next_property == 0 || property > PROP_NUMBER_MAX ||
        prop_list_start(memory, object_table, object, &cursor) != PROP_OK) {
        return PROP_ERROR;
    }
    want_first = (property == 0);
    for (;;) {
        if (prop_read_entry(memory, cursor, &number, &data_addr, &len, &next) != PROP_OK) {
            return PROP_ERROR;
        }
        if (want_first) {
            *next_property = number;   /* 0 if the object has no properties
                                        * left from this point */
            return PROP_OK;
        }
        if (number == 0) {
            return PROP_ERROR;         /* `property` was never in the list */
        }
        if (number == property) {
            want_first = 1;            /* report the entry after this one */
        }
        cursor = next;
    }
}
