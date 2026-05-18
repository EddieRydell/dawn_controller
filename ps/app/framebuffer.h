#ifndef DONDER_FRAMEBUFFER_H
#define DONDER_FRAMEBUFFER_H

#include <stdint.h>

#include "config.h"

void framebuffer_init(void);
uint32_t framebuffer_begin_write_bank(void);
void framebuffer_clear_bank(uint32_t bank);
void framebuffer_write_rgb(uint32_t bank, uint32_t output, uint32_t pixel, uint8_t r, uint8_t g, uint8_t b);
void framebuffer_flush_bank(uint32_t bank);
uintptr_t framebuffer_base_address(void);

#endif
