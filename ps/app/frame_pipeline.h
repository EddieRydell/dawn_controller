#ifndef FRAME_PIPELINE_H
#define FRAME_PIPELINE_H

#include <stdint.h>

#include "app_config.h"

void frame_pipeline_init(void);
uint32_t *frame_pipeline_inactive_words(void);
void frame_pipeline_generate_test_pattern(uint32_t frame_number);
int frame_pipeline_commit(void);
int frame_pipeline_configure(uint32_t active_count, const uint32_t lengths[4]);

#endif
