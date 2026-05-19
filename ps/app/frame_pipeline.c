#include "frame_pipeline.h"

#include "pl_ingest.h"

#define FRAME_BANKS 2u

static uint32_t g_frame_words[FRAME_BANKS][DONDER_WORDS_PER_FRAME];
static uint32_t g_write_bank;

void frame_pipeline_init(void)
{
    g_write_bank = 0u;
    for (uint32_t bank = 0u; bank < FRAME_BANKS; ++bank) {
        for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
            g_frame_words[bank][word] = 0u;
        }
    }
}

uint32_t *frame_pipeline_inactive_words(void)
{
    return g_frame_words[g_write_bank];
}

void frame_pipeline_generate_test_pattern(uint32_t frame_number)
{
    uint32_t *words = frame_pipeline_inactive_words();

    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        for (uint32_t pixel = 0u; pixel < DONDER_PIXELS_PER_OUTPUT; ++pixel) {
            uint32_t index = (pixel * DONDER_OUTPUT_COUNT) + output;
            uint32_t phase = (pixel + frame_number + (output * 64u)) & 0xffu;
            uint32_t r = phase;
            uint32_t g = 255u - phase;
            uint32_t b = (frame_number + output) & 0xffu;
            words[index] = (r << 16) | (g << 8) | b;
        }
    }
}

int frame_pipeline_commit(void)
{
    if (pl_ingest_write_frame(frame_pipeline_inactive_words(), DONDER_WORDS_PER_FRAME) != PL_INGEST_OK) {
        return -1;
    }

    g_write_bank ^= 1u;
    return 0;
}
