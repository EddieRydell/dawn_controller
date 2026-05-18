#ifndef DONDER_CONFIG_H
#define DONDER_CONFIG_H

#include <stdint.h>

#define DONDER_MAX_OUTPUTS 4u
#define DONDER_MAX_PIXELS_PER_OUTPUT 1024u
#define DONDER_FRAME_BANKS 3u

typedef enum {
    COLOR_ORDER_RGB = 0,
    COLOR_ORDER_GRB = 1,
    COLOR_ORDER_BRG = 2,
    COLOR_ORDER_BGR = 3
} color_order_t;

typedef struct {
    uint16_t pixel_count;
    uint8_t color_order;
    uint8_t brightness_limit;
    uint8_t reversed;
    uint8_t enabled;
    uint8_t reserved[2];
} output_config_t;

typedef struct {
    uint32_t magic;
    uint16_t version;
    uint16_t output_count;
    output_config_t outputs[DONDER_MAX_OUTPUTS];
} controller_config_t;

extern controller_config_t g_config;

void config_load_defaults(void);

#endif
