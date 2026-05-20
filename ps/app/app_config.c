#include "app_config.h"

const app_config_t g_app_config = {
    .output_count = DONDER_OUTPUT_COUNT,
    .pixels_per_output = DONDER_PIXELS_PER_OUTPUT,
    .words_per_frame = DONDER_WORDS_PER_FRAME,
    .e131_port = DONDER_E131_PORT,
    .first_universe = DONDER_FIRST_UNIVERSE,
    .mac = {0x02u, 0x0au, 0x35u, 0x07u, 0x00u, 0x02u},
    .ip = {192u, 168u, 7u, 2u},
    .netmask = {255u, 255u, 255u, 0u},
    .gateway = {0u, 0u, 0u, 0u},
    .host_test_ip = {DONDER_HOST_TEST_IP0, DONDER_HOST_TEST_IP1, DONDER_HOST_TEST_IP2, DONDER_HOST_TEST_IP3},
};
