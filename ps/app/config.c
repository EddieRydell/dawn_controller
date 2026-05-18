#include "config.h"

controller_config_t g_config;

void config_load_defaults(void)
{
    g_config.magic = 0x444f4e44u;
    g_config.version = 1u;

    g_config.output_count = DONDER_MAX_OUTPUTS;
    for (uint32_t i = 0u; i < g_config.output_count; ++i) {
        g_config.outputs[i].pixel_count = 16u;
        g_config.outputs[i].color_order = COLOR_ORDER_GRB;
        g_config.outputs[i].brightness_limit = 255u;
        g_config.outputs[i].reversed = 0u;
        g_config.outputs[i].enabled = 1u;
    }
}
