#include "app_config.h"

const app_config_t g_app_config = {
    .output_count = DONDER_OUTPUT_COUNT,
    .pixels_per_output = DONDER_PIXELS_PER_OUTPUT,
    .words_per_frame = DONDER_WORDS_PER_FRAME,
    .e131_port = DONDER_E131_PORT,
    .first_universe = DONDER_FIRST_UNIVERSE,
};
