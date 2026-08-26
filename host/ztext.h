#ifndef ZRUN3_ZTEXT_H
#define ZRUN3_ZTEXT_H

#include <stdint.h>

typedef int (*ztext_emit_fn)(char character, void *context);

int ztext_decode(const uint8_t *packed, uint16_t length,
                 ztext_emit_fn emit, void *context);

#endif