#include <stdint.h>

#include "app_config.h"
#include "frame_pipeline.h"
#include "pl_ingest.h"
#include "sleep.h"
#include "xil_printf.h"

static void fatal(const char *message, int code)
{
    xil_printf("FATAL %s code=%d\r\n", message, code);
    while (1) {
        pl_ingest_drive_pins(0x0fu);
        usleep(100000u);
        pl_ingest_drive_pins(0x00u);
        usleep(100000u);
    }
}

int main(void)
{
    uint32_t frame_number = 0u;

    xil_printf("\r\ndonder controller starting\r\n");
    xil_printf("outputs=%lu pixels_per_output=%lu frame_words=%lu e131_port=%u first_universe=%u\r\n",
               (unsigned long)g_app_config.output_count,
               (unsigned long)g_app_config.pixels_per_output,
               (unsigned long)g_app_config.words_per_frame,
               g_app_config.e131_port,
               g_app_config.first_universe);

    pl_ingest_result_t init_result = pl_ingest_init(g_app_config.words_per_frame);
    if (init_result != PL_INGEST_OK) {
        fatal("pl_init", init_result);
    }

    pl_ingest_result_t self_test_result = pl_ingest_self_test();
    if (self_test_result != PL_INGEST_OK) {
        fatal("pl_self_test", self_test_result);
    }

    frame_pipeline_init();
    xil_printf("foundation ready\r\n");

    while (1) {
        frame_pipeline_generate_test_pattern(frame_number);
        if (frame_pipeline_commit() != 0) {
            fatal("frame_commit", -1);
        }

        pl_ingest_drive_pins(1u << (frame_number & 3u));
        frame_number++;
        usleep(25000u);
    }
}
