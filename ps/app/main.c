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
        usleep(100000u);
    }
}

int main(void)
{
    uint32_t frame_number = 0u;
    uint32_t accepted_frames = 0u;
    uint32_t dropped_frames = 0u;

    xil_printf("\r\ndonder controller starting\r\n");
    xil_printf("max_outputs=%u max_pixels_per_output=%u max_frame_words=%u e131_port=%u first_universe=%u\r\n",
               (unsigned int)g_app_config.output_count,
               (unsigned int)g_app_config.pixels_per_output,
               (unsigned int)g_app_config.words_per_frame,
               (unsigned int)g_app_config.e131_port,
               (unsigned int)g_app_config.first_universe);

    pl_ingest_result_t init_result = pl_ingest_init(g_app_config.words_per_frame);
    if (init_result != PL_INGEST_OK) {
        fatal("pl_init", init_result);
    }

    pl_ingest_result_t self_test_result = pl_ingest_self_test();
    if (self_test_result != PL_INGEST_OK) {
        fatal("pl_self_test", self_test_result);
    }

    frame_pipeline_init();
    const uint32_t startup_lengths[DONDER_OUTPUT_COUNT] = {20u, 20u, 20u, 20u};
    if (frame_pipeline_configure(DONDER_OUTPUT_COUNT, startup_lengths) != 0) {
        fatal("startup_configure", -1);
    }
    frame_pipeline_generate_test_pattern(frame_number);
    if (frame_pipeline_commit() != 0) {
        fatal("initial_frame_commit", -1);
    }
    accepted_frames++;
    frame_number++;

    pl_ingest_result_t consumer_result = pl_ingest_enable_consumer();
    if (consumer_result != PL_INGEST_OK) {
        fatal("pl_enable_consumer", consumer_result);
    }
    xil_printf("foundation ready\r\n");

    while (1) {
        int commit_result;

        frame_pipeline_generate_test_pattern(frame_number);
        commit_result = frame_pipeline_commit();
        if (commit_result == 0) {
            accepted_frames++;
        } else if (commit_result > 0) {
            dropped_frames++;
        } else {
            fatal("frame_commit", -1);
        }

        if (((accepted_frames + dropped_frames) % 100u) == 0u) {
            pl_ingest_snapshot_t snapshot;
            pl_ingest_snapshot(&snapshot);
            xil_printf("frames accepted=%u dropped=%u pl_dropped=%u rejected=%u write_valid=%u busy_bank=0x%08x consumer_frames=%u active_outputs=%u lengths=[%u,%u,%u,%u] config_status=0x%08x\r\n",
                       (unsigned int)accepted_frames,
                       (unsigned int)dropped_frames,
                       (unsigned int)snapshot.frame_dropped,
                       (unsigned int)snapshot.frame_rejected,
                       (unsigned int)snapshot.write_bank_valid,
                       (unsigned int)snapshot.busy_bank,
                       (unsigned int)snapshot.consumer_frame_count,
                       (unsigned int)snapshot.active_output_count,
                       (unsigned int)snapshot.strand_pixel_count[0],
                       (unsigned int)snapshot.strand_pixel_count[1],
                       (unsigned int)snapshot.strand_pixel_count[2],
                       (unsigned int)snapshot.strand_pixel_count[3],
                       (unsigned int)snapshot.config_status);
        }

        frame_number++;
        usleep(25000u);
    }
}
