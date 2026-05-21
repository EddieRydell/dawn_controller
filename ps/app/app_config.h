#ifndef APP_CONFIG_H
#define APP_CONFIG_H

#include <stdint.h>

#define DAWN_OUTPUT_COUNT 4u
#define DAWN_PIXELS_PER_OUTPUT 1024u
#define DAWN_WORDS_PER_FRAME (DAWN_OUTPUT_COUNT * DAWN_PIXELS_PER_OUTPUT)
#define DAWN_OUTPUT_INVERT_MASK 0x0fu

#define DAWN_E131_PORT 5568u
#define DAWN_FIRST_UNIVERSE 1u
#define DAWN_SLOTS_PER_UNIVERSE 510u
#define DAWN_E131_BLACKOUT_TIMEOUT_MS 500u
#define DAWN_E131_ACCEPT_PREVIEW 0u
#define DAWN_E131_DEFAULT_SYNC_ADDRESS 63999u
#define DAWN_HOST_TEST_IP0 192u
#define DAWN_HOST_TEST_IP1 168u
#define DAWN_HOST_TEST_IP2 7u
#define DAWN_HOST_TEST_IP3 1u

typedef struct {
    uint32_t output_count;
    uint32_t pixels_per_output;
    uint32_t words_per_frame;
    uint32_t output_invert_mask;
    uint16_t e131_port;
    uint16_t first_universe;
    uint8_t mac[6];
    uint8_t ip[4];
    uint8_t netmask[4];
    uint8_t gateway[4];
    uint8_t host_test_ip[4];
} app_config_t;

extern const app_config_t g_app_config;

#endif
