#include "pl_if.h"

#include "xil_io.h"
#include "xparameters.h"

#ifndef PL_CTRL_BASEADDR
#if defined(XPAR_CONTROLLER_CORE_0_BASEADDR)
#define PL_CTRL_BASEADDR XPAR_CONTROLLER_CORE_0_BASEADDR
#elif defined(XPAR_CONTROLLER_CORE_BD_0_BASEADDR)
#define PL_CTRL_BASEADDR XPAR_CONTROLLER_CORE_BD_0_BASEADDR
#else
#error "Missing AXI register base address for controller_core_0 in xparameters.h"
#endif
#endif

static inline void pl_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(PL_CTRL_BASEADDR + offset, value);
}

static inline uint32_t pl_read(uint32_t offset)
{
    return Xil_In32(PL_CTRL_BASEADDR + offset);
}

void pl_init(const controller_config_t *config)
{
    pl_write(PL_REG_CONTROL, 0u);
    pl_write(PL_REG_OUTPUT_COUNT, config->output_count);

    for (uint32_t i = 0u; i < config->output_count; ++i) {
        uint32_t base = PL_REG_OUTPUT_BASE + (i * PL_REG_OUTPUT_STRIDE);
        pl_write(base + 0x0u, config->outputs[i].pixel_count);
        pl_write(base + 0x4u, i * DONDER_MAX_PIXELS_PER_OUTPUT * sizeof(uint32_t));
        pl_write(base + 0x8u,
                 ((uint32_t)config->outputs[i].enabled << 0) |
                 ((uint32_t)config->outputs[i].reversed << 1) |
                 ((uint32_t)config->outputs[i].color_order << 8));
    }

    pl_write(PL_REG_WRITE_BANK, 0u);
    pl_write(PL_REG_CONTROL, PL_ENABLE);
}

void pl_set_frame_base_addr(uint32_t address)
{
    pl_write(PL_REG_FRAME_BASE_ADDR, address);
}

uint32_t pl_get_status(void)
{
    return pl_read(PL_REG_STATUS);
}

uint32_t pl_get_frame_counter(void)
{
    return pl_read(PL_REG_FRAME_COUNTER);
}

uint32_t pl_get_output_count(void)
{
    return pl_read(PL_REG_OUTPUT_COUNT);
}

uint32_t pl_get_max_pixels_per_output(void)
{
    return pl_read(PL_REG_MAX_PIXELS_PER_OUTPUT);
}

uint32_t pl_ready_for_frame(void)
{
    return (pl_get_status() & PL_READY_FOR_FRAME) != 0u;
}

void pl_irq_enable(uint32_t mask)
{
    pl_write(PL_REG_IRQ_ENABLE, mask);
}

void pl_irq_disable(void)
{
    pl_write(PL_REG_IRQ_ENABLE, 0u);
}

uint32_t pl_irq_get_status(void)
{
    return pl_read(PL_REG_IRQ_STATUS);
}

void pl_irq_ack(uint32_t mask)
{
    pl_write(PL_REG_IRQ_STATUS, mask);
}

void pl_set_write_bank(uint32_t bank)
{
    pl_write(PL_REG_WRITE_BANK, bank);
}

void pl_commit_frame(uint32_t bank)
{
    pl_write(PL_REG_WRITE_BANK, bank);
    pl_write(PL_REG_CONTROL, PL_ENABLE | PL_COMMIT_FRAME);
    pl_write(PL_REG_CONTROL, PL_ENABLE);
}

uint32_t pl_get_active_bank(void)
{
    return pl_read(PL_REG_ACTIVE_BANK);
}
