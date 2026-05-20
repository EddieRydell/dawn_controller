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
            xil_printf("frames accepted=%lu dropped=%lu pl_dropped=%lu rejected=%lu write_valid=%lu busy_bank=0x%08lx consumer_frames=%lu\r\n",
                       (unsigned long)accepted_frames,
                       (unsigned long)dropped_frames,
                       (unsigned long)snapshot.frame_dropped,
                       (unsigned long)snapshot.frame_rejected,
                       (unsigned long)snapshot.write_bank_valid,
                       (unsigned long)snapshot.busy_bank,
                       (unsigned long)snapshot.consumer_frame_count);
        }

        frame_number++;
        usleep(25000u);
    }
}
