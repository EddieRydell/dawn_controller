#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stdint.h>

#define DONDER_OUTPUT_COUNT 4u
#define DONDER_PIXELS_PER_OUTPUT 1024u
#define DONDER_WORDS_PER_FRAME (DONDER_OUTPUT_COUNT * DONDER_PIXELS_PER_OUTPUT)

#define DONDER_E131_PORT 5568u
#define DONDER_FIRST_UNIVERSE 1u
#define DONDER_SLOTS_PER_UNIVERSE 510u

typedef struct {
    uint32_t output_count;
    uint32_t pixels_per_output;
    uint32_t words_per_frame;
    uint16_t e131_port;
    uint16_t first_universe;
} app_config_t;

extern const app_config_t g_app_config;

#endif
