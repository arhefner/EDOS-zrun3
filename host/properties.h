#ifndef ZRUN3_PROPERTIES_H
#define ZRUN3_PROPERTIES_H

#include <stdint.h>

#include "story_mem.h"

/* V3 property numbers run 1-31; 0 is reserved as the get_prop_next
 * "start from the first property" sentinel. */
#define PROP_NUMBER_MAX 31

/* addr = 0 and len = 0 both mean "object has no such property". */
int prop_get_addr(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t property, uint16_t *addr);
int prop_get_len(const struct story_mem *memory, uint16_t addr, uint8_t *len);

/* Falls back to the property-defaults table (object_table's first
 * OBJ_PROP_DEFAULTS_SIZE bytes) when the object doesn't have the
 * property itself. Properties longer than 2 bytes yield their first
 * word, matching common interpreter practice for a case the Z-machine
 * standard leaves to the game to avoid triggering. */
int prop_get(const struct story_mem *memory, uint16_t object_table,
            uint8_t object, uint8_t property, uint16_t *value);

/* property = 0 returns the object's first property number. Returns an
 * error if `property` isn't actually one of the object's properties. */
int prop_get_next(const struct story_mem *memory, uint16_t object_table,
                  uint8_t object, uint8_t property, uint8_t *next_property);

#endif
