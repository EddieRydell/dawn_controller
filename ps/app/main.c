#include "config.h"
#include "framebuffer.h"
#include "pl_if.h"

#include "xil_cache.h"
#include "xil_printf.h"

static void wait_for_frame_complete(void)
{
    uint32_t saw_busy = 0u;
    uint32_t timeout = 1000000u;

    while (timeout-- != 0u) {
        uint32_t status = pl_get_status();
        if ((status & PL_BUSY) != 0u) {
            saw_busy = 1u;
        } else if (saw_busy != 0u) {
            break;
        }
    }
}

static void write_sample_frame(uint32_t bank, uint32_t phase)
{
    for (uint32_t output = 0u; output < g_config.output_count; ++output) {
        uint32_t pixels = g_config.outputs[output].pixel_count;
        for (uint32_t pixel = 0u; pixel < pixels; ++pixel) {
            switch ((pixel + phase) & 3u) {
            case 0u:
                framebuffer_write_rgb(bank, output, pixel, 255u, 0u, 0u);
                break;
            case 1u:
                framebuffer_write_rgb(bank, output, pixel, 0u, 255u, 0u);
                break;
            case 2u:
                framebuffer_write_rgb(bank, output, pixel, 0u, 0u, 255u);
                break;
            default:
                framebuffer_write_rgb(bank, output, pixel, 255u, 255u, 255u);
                break;
            }
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

    uint32_t phase = 0u;
    while (1) {
        uint32_t bank = framebuffer_begin_write_bank();
        write_sample_frame(bank, phase);
        pl_commit_frame(bank);
        wait_for_frame_complete();
        phase++;
    }
}
