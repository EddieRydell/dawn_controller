#include "frame_pipeline.h"

#include "pl_ingest.h"

#define FRAME_BANKS 2u

static uint32_t g_frame_words[FRAME_BANKS][DONDER_WORDS_PER_FRAME];
static uint32_t g_write_bank;
static uint32_t g_active_output_count;
static uint32_t g_strand_pixel_count[DONDER_OUTPUT_COUNT];
static uint32_t g_required_words;

static uint32_t clamp_u32(uint32_t value, uint32_t max_value)
{
    return value < max_value ? value : max_value;
}

static uint32_t required_words_for(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    uint32_t required_words = 0u;

    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        if (output < active_count && lengths[output] > 0u) {
            uint32_t required = ((lengths[output] - 1u) * DONDER_OUTPUT_COUNT) + output + 1u;
            if (required > required_words) {
                required_words = required;
            }
        }
    }

    return required_words;
}

static void apply_local_config(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    g_active_output_count = clamp_u32(active_count, DONDER_OUTPUT_COUNT);
    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        g_strand_pixel_count[output] = clamp_u32(lengths[output], DONDER_PIXELS_PER_OUTPUT);
    }
    g_required_words = required_words_for(g_active_output_count, g_strand_pixel_count);
}

static void clear_inactive_frame(void)
{
    uint32_t *words = frame_pipeline_inactive_words();

    for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
        words[word] = 0u;
    }
}

void frame_pipeline_init(void)
{
    pl_ingest_config_t config;

    g_write_bank = 0u;
    for (uint32_t bank = 0u; bank < FRAME_BANKS; ++bank) {
        for (uint32_t word = 0u; word < DONDER_WORDS_PER_FRAME; ++word) {
            g_frame_words[bank][word] = 0u;
        }
    }

    if (pl_ingest_get_config(&config) == PL_INGEST_OK) {
        apply_local_config(config.effective_active_output_count, config.effective_strand_pixel_count);
    } else {
        const uint32_t default_lengths[DONDER_OUTPUT_COUNT] = {
            DONDER_PIXELS_PER_OUTPUT,
            DONDER_PIXELS_PER_OUTPUT,
            DONDER_PIXELS_PER_OUTPUT,
            DONDER_PIXELS_PER_OUTPUT,
        };
        apply_local_config(DONDER_OUTPUT_COUNT, default_lengths);
    }
}

uint32_t *frame_pipeline_inactive_words(void)
{
    return g_frame_words[g_write_bank];
}

void frame_pipeline_generate_test_pattern(uint32_t frame_number)
{
    uint32_t *words = frame_pipeline_inactive_words();

    for (uint32_t word = 0u; word < g_required_words; ++word) {
        words[word] = 0u;
    }

    for (uint32_t output = 0u; output < g_active_output_count; ++output) {
        for (uint32_t pixel = 0u; pixel < g_strand_pixel_count[output]; ++pixel) {
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
    pl_ingest_result_t result = pl_ingest_write_frame(frame_pipeline_inactive_words(), g_required_words);

    if (result == PL_INGEST_NO_FREE_BANK) {
        return 1;
    }
    if (result != PL_INGEST_OK) {
        return -1;
    }

    g_write_bank ^= 1u;
    return 0;
}

int frame_pipeline_configure(uint32_t active_count, const uint32_t lengths[DONDER_OUTPUT_COUNT])
{
    uint32_t new_active_count;
    uint32_t new_lengths[DONDER_OUTPUT_COUNT];
    int needs_black_frame = 0;

    if (lengths == 0) {
        return -1;
    }

    new_active_count = clamp_u32(active_count, DONDER_OUTPUT_COUNT);
    for (uint32_t output = 0u; output < DONDER_OUTPUT_COUNT; ++output) {
        new_lengths[output] = clamp_u32(lengths[output], DONDER_PIXELS_PER_OUTPUT);
        if (output >= new_active_count) {
            new_lengths[output] = 0u;
        }
        if (output < g_active_output_count
            && (output >= new_active_count || new_lengths[output] < g_strand_pixel_count[output])) {
            needs_black_frame = 1;
        }
    }

    if (needs_black_frame) {
        int commit_result;
        clear_inactive_frame();
        commit_result = frame_pipeline_commit();
        if (commit_result != 0) {
            return commit_result;
        }
    }

    if (pl_ingest_configure_strands(active_count, lengths) != PL_INGEST_OK) {
        return -1;
    }

    apply_local_config(new_active_count, new_lengths);
    return 0;
}
