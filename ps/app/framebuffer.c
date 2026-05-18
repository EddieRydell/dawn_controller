#include "framebuffer.h"

#include "xil_cache.h"

#define FRAME_PIXELS_PER_BANK (DONDER_MAX_OUTPUTS * DONDER_MAX_PIXELS_PER_OUTPUT)

static uint32_t g_framebanks[DONDER_FRAME_BANKS][FRAME_PIXELS_PER_BANK] __attribute__((aligned(64)));
static uint32_t g_next_bank;

void framebuffer_init(void)
{
    for (uint32_t bank = 0u; bank < DONDER_FRAME_BANKS; ++bank) {
        framebuffer_clear_bank(bank);
    }
    g_next_bank = 0u;
}

uint32_t framebuffer_begin_write_bank(void)
{
    uint32_t bank = g_next_bank;
    g_next_bank = (g_next_bank + 1u) % DONDER_FRAME_BANKS;
    return bank;
}

void framebuffer_clear_bank(uint32_t bank)
{
    if (bank >= DONDER_FRAME_BANKS) {
        return;
    }

    for (uint32_t i = 0u; i < FRAME_PIXELS_PER_BANK; ++i) {
        g_framebanks[bank][i] = 0u;
    }

    framebuffer_flush_bank(bank);
}

void framebuffer_write_rgb(uint32_t bank, uint32_t output, uint32_t pixel, uint8_t r, uint8_t g, uint8_t b)
{
    if (bank >= DONDER_FRAME_BANKS || output >= DONDER_MAX_OUTPUTS || pixel >= DONDER_MAX_PIXELS_PER_OUTPUT) {
        return;
    }

    uint32_t index = (output * DONDER_MAX_PIXELS_PER_OUTPUT) + pixel;
    g_framebanks[bank][index] = ((uint32_t)r << 16) | ((uint32_t)g << 8) | (uint32_t)b;
}

void framebuffer_flush_bank(uint32_t bank)
{
    if (bank >= DONDER_FRAME_BANKS) {
        return;
    }

    Xil_DCacheFlushRange((INTPTR)&g_framebanks[bank][0],
                         FRAME_PIXELS_PER_BANK * sizeof(uint32_t));
}

uintptr_t framebuffer_base_address(void)
{
    return (uintptr_t)&g_framebanks[0][0];
}
