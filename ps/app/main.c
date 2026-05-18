#include "config.h"
#include "framebuffer.h"
#include "pl_if.h"

#include "xil_cache.h"
#include "xil_printf.h"

static void wait_for_frame_ready(void)
{
    while (!pl_ready_for_frame()) {
    }
}

static void write_sample_frame(uint32_t bank)
{
    for (uint32_t output = 0u; output < g_config.output_count; ++output) {
        uint32_t pixels = g_config.outputs[output].pixel_count;
        for (uint32_t pixel = 0u; pixel < pixels; ++pixel) {
            framebuffer_write_rgb(bank, output, pixel, 255u, 0u, 0u);
        }
    }
    framebuffer_flush_bank(bank);
}

int main(void)
{
    Xil_ICacheEnable();
    Xil_DCacheEnable();

    xil_printf("donder ps starting\r\n");

    config_load_defaults();
    framebuffer_init();
    pl_init(&g_config);
    pl_set_frame_base_addr((uint32_t)framebuffer_base_address());

    xil_printf("pl output_count=%lu max_pixels=%lu status=0x%08lx frame_counter=%lu\r\n",
               (unsigned long)pl_get_output_count(),
               (unsigned long)pl_get_max_pixels_per_output(),
               (unsigned long)pl_get_status(),
               (unsigned long)pl_get_frame_counter());

    while (1) {
        uint32_t bank = framebuffer_begin_write_bank();
        write_sample_frame(bank);
        wait_for_frame_ready();
        pl_commit_frame(bank);
        wait_for_frame_ready();
    }
}
