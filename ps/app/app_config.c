#include "app_config.h"

const app_config_t g_app_config = {
    .output_count = DAWN_OUTPUT_COUNT,
    .pin_output_count = DAWN_PIN_OUTPUT_COUNT,
    .pixels_per_output = DAWN_PIXELS_PER_OUTPUT,
    .words_per_frame = DAWN_WORDS_PER_FRAME,
    .default_active_output_count = DAWN_DEFAULT_ACTIVE_OUTPUT_COUNT,
    .default_strand_pixel_count = DAWN_DEFAULT_STRAND_PIXEL_COUNT,
    .output_invert_mask = DAWN_OUTPUT_INVERT_MASK,
    .e131_port = DAWN_E131_PORT,
    .first_universe = DAWN_FIRST_UNIVERSE,
    .mac = {DAWN_PL_MAC0, DAWN_PL_MAC1, DAWN_PL_MAC2, DAWN_PL_MAC3, DAWN_PL_MAC4, DAWN_PL_MAC5},
    .ip = {DAWN_PL_BOARD_IP0, DAWN_PL_BOARD_IP1, DAWN_PL_BOARD_IP2, DAWN_PL_BOARD_IP3},
    .netmask = {DAWN_PL_NETMASK_IP0, DAWN_PL_NETMASK_IP1, DAWN_PL_NETMASK_IP2, DAWN_PL_NETMASK_IP3},
    .gateway = {DAWN_PL_GATEWAY_IP0, DAWN_PL_GATEWAY_IP1, DAWN_PL_GATEWAY_IP2, DAWN_PL_GATEWAY_IP3},
    .host_test_ip = {DAWN_HOST_TEST_IP0, DAWN_HOST_TEST_IP1, DAWN_HOST_TEST_IP2, DAWN_HOST_TEST_IP3},
};
