#include "objects.h"

enum { OBJ_OK = 0, OBJ_ERROR = -1 };

int obj_entry_addr(uint16_t object_table, uint8_t object, uint16_t *addr)
{
    if (addr == 0 || object == 0) {
        return OBJ_ERROR;
    }
    *addr = (uint16_t)(object_table + OBJ_PROP_DEFAULTS_SIZE +
                       (object - 1) * OBJ_ENTRY_SIZE);
    return OBJ_OK;
}

static int obj_read_link(const struct story_mem *memory, uint16_t object_table,
                         uint8_t object, uint16_t offset, uint8_t *value)
{
    uint16_t addr;

    if (value == 0 || obj_entry_addr(object_table, object, &addr) != OBJ_OK ||
        story_mem_read8(memory, (uint16_t)(addr + offset), value) != 0) {
        return OBJ_ERROR;
    }
    return OBJ_OK;
}

static int obj_write_link(struct story_mem *memory, uint16_t object_table,
                          uint8_t object, uint16_t offset, uint8_t value)
{
    uint16_t addr;

    if (obj_entry_addr(object_table, object, &addr) != OBJ_OK ||
        story_mem_write8(memory, (uint16_t)(addr + offset), value) != 0) {
        return OBJ_ERROR;
    }
    return OBJ_OK;
}

int obj_get_parent(const struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint8_t *parent)
{
    return obj_read_link(memory, object_table, object, 4, parent);
}

int obj_get_sibling(const struct story_mem *memory, uint16_t object_table,
                    uint8_t object, uint8_t *sibling)
{
    return obj_read_link(memory, object_table, object, 5, sibling);
}

int obj_get_child(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t *child)
{
    return obj_read_link(memory, object_table, object, 6, child);
}

static int obj_set_parent(struct story_mem *memory, uint16_t object_table,
                          uint8_t object, uint8_t parent)
{
    return obj_write_link(memory, object_table, object, 4, parent);
}

static int obj_set_sibling(struct story_mem *memory, uint16_t object_table,
                           uint8_t object, uint8_t sibling)
{
    return obj_write_link(memory, object_table, object, 5, sibling);
}

static int obj_set_child(struct story_mem *memory, uint16_t object_table,
                         uint8_t object, uint8_t child)
{
    return obj_write_link(memory, object_table, object, 6, child);
}

int obj_test_attr(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t attribute, int *is_set)
{
    uint16_t addr;
    uint8_t byte;

    if (is_set == 0 || attribute >= OBJ_ATTR_COUNT ||
        obj_entry_addr(object_table, object, &addr) != OBJ_OK ||
        story_mem_read8(memory, (uint16_t)(addr + attribute / 8), &byte) != 0) {
        return OBJ_ERROR;
    }
    *is_set = (byte & (0x80 >> (attribute % 8))) != 0;
    return OBJ_OK;
}

static int obj_write_attr(struct story_mem *memory, uint16_t object_table,
                          uint8_t object, uint8_t attribute, int set)
{
    uint16_t addr;
    uint8_t byte;
    uint8_t mask;

    if (attribute >= OBJ_ATTR_COUNT ||
        obj_entry_addr(object_table, object, &addr) != OBJ_OK) {
        return OBJ_ERROR;
    }
    addr = (uint16_t)(addr + attribute / 8);
    mask = (uint8_t)(0x80 >> (attribute % 8));
    if (story_mem_read8(memory, addr, &byte) != 0) {
        return OBJ_ERROR;
    }
    byte = set ? (uint8_t)(byte | mask) : (uint8_t)(byte & ~mask);
    return story_mem_write8(memory, addr, byte) == 0 ? OBJ_OK : OBJ_ERROR;
}

int obj_set_attr(struct story_mem *memory, uint16_t object_table,
                 uint8_t object, uint8_t attribute)
{
    return obj_write_attr(memory, object_table, object, attribute, 1);
}

int obj_clear_attr(struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint8_t attribute)
{
    return obj_write_attr(memory, object_table, object, attribute, 0);
}

int obj_remove(struct story_mem *memory, uint16_t object_table,
              uint8_t object)
{
    uint8_t parent;
    uint8_t sibling;
    uint8_t cursor;
    uint8_t next;

    if (object == 0 || obj_get_parent(memory, object_table, object, &parent) != 0) {
        return OBJ_ERROR;
    }
    if (parent == 0) {
        return OBJ_OK;              /* already detached: no-op */
    }
    if (obj_get_sibling(memory, object_table, object, &sibling) != 0) {
        return OBJ_ERROR;
    }
    if (obj_get_child(memory, object_table, parent, &cursor) != 0) {
        return OBJ_ERROR;
    }
    if (cursor == object) {
        if (obj_set_child(memory, object_table, parent, sibling) != 0) {
            return OBJ_ERROR;
        }
    } else {
        while (cursor != 0) {
            if (obj_get_sibling(memory, object_table, cursor, &next) != 0) {
                return OBJ_ERROR;
            }
            if (next == object) {
                if (obj_set_sibling(memory, object_table, cursor, sibling) != 0) {
                    return OBJ_ERROR;
                }
                break;
            }
            cursor = next;
        }
        if (cursor == 0) {
            return OBJ_ERROR;       /* parent's child list never held object */
        }
    }
    if (obj_set_parent(memory, object_table, object, 0) != 0 ||
        obj_set_sibling(memory, object_table, object, 0) != 0) {
        return OBJ_ERROR;
    }
    return OBJ_OK;
}

int obj_insert(struct story_mem *memory, uint16_t object_table,
              uint8_t object, uint8_t destination)
{
    uint8_t former_child;

    if (object == 0 || destination == 0 ||
        obj_remove(memory, object_table, object) != 0 ||
        obj_get_child(memory, object_table, destination, &former_child) != 0) {
        return OBJ_ERROR;
    }
    if (obj_set_sibling(memory, object_table, object, former_child) != 0 ||
        obj_set_child(memory, object_table, destination, object) != 0 ||
        obj_set_parent(memory, object_table, object, destination) != 0) {
        return OBJ_ERROR;
    }
    return OBJ_OK;
}

int obj_prop_table_addr(const struct story_mem *memory, uint16_t object_table,
                        uint8_t object, uint16_t *addr)
{
    uint16_t entry;

    if (addr == 0 || obj_entry_addr(object_table, object, &entry) != OBJ_OK ||
        story_mem_read16(memory, (uint16_t)(entry + 7), addr) != 0) {
        return OBJ_ERROR;
    }
    return OBJ_OK;
}

int obj_short_name(const struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint16_t *addr, uint16_t *length)
{
    uint16_t table;
    uint8_t word_count;

    if (addr == 0 || length == 0 ||
        obj_prop_table_addr(memory, object_table, object, &table) != OBJ_OK ||
        story_mem_read8(memory, table, &word_count) != 0) {
        return OBJ_ERROR;
    }
    *addr = (uint16_t)(table + 1);
    *length = (uint16_t)(word_count * 2);
    return OBJ_OK;
}
