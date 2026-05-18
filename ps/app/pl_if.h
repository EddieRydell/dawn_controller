#ifndef PL_IF_H
#define PL_IF_H

#include <stdint.h>

#include "config.h"
#include "pl_regs.h"

void pl_init(const controller_config_t *config);
void pl_set_frame_base_addr(uint32_t address);
uint32_t pl_get_status(void);
uint32_t pl_get_frame_counter(void);
uint32_t pl_get_output_count(void);
uint32_t pl_get_max_pixels_per_output(void);
void pl_set_write_bank(uint32_t bank);
void pl_commit_frame(uint32_t bank);
uint32_t pl_get_active_bank(void);

#endif
