#ifndef ZRUN3_OBJECTS_H
#define ZRUN3_OBJECTS_H

#include <stdint.h>

#include "story_mem.h"

/* V3 object table: 31 two-byte property defaults, then 9-byte object
 * entries (4 attribute bytes, parent/sibling/child, 2-byte property
 * table address), objects numbered from 1. Object 0 means "no object"
 * and is not a valid object to query. */
#define OBJ_PROP_DEFAULTS_COUNT 31
#define OBJ_PROP_DEFAULTS_SIZE  (OBJ_PROP_DEFAULTS_COUNT * 2)
#define OBJ_ENTRY_SIZE          9
#define OBJ_ATTR_COUNT          32

int obj_entry_addr(uint16_t object_table, uint8_t object, uint16_t *addr);

int obj_get_parent(const struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint8_t *parent);
int obj_get_sibling(const struct story_mem *memory, uint16_t object_table,
                    uint8_t object, uint8_t *sibling);
int obj_get_child(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t *child);

int obj_test_attr(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t attribute, int *is_set);
int obj_set_attr(struct story_mem *memory, uint16_t object_table,
                 uint8_t object, uint8_t attribute);
int obj_clear_attr(struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint8_t attribute);

int obj_remove(struct story_mem *memory, uint16_t object_table,
              uint8_t object);
int obj_insert(struct story_mem *memory, uint16_t object_table,
              uint8_t object, uint8_t destination);

int obj_prop_table_addr(const struct story_mem *memory, uint16_t object_table,
                        uint8_t object, uint16_t *addr);

/* The short name is the packed Z-text immediately after the property
 * table's leading length-in-words byte -- ready to hand to
 * ztext_decode(). *length is in bytes (2 * the story's word count). */
int obj_short_name(const struct story_mem *memory, uint16_t object_table,
                   uint8_t object, uint16_t *addr, uint16_t *length);

#endif
