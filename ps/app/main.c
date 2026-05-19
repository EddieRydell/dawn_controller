#include "config.h"
#include "framebuffer.h"
#include "pl_if.h"

#include "xil_cache.h"
#include "xil_exception.h"
#include "xil_printf.h"
#include "xparameters.h"
#include "xscugic.h"

#if defined(XPAR_FABRIC_CONTROLLER_CORE_0_IRQ_INTR)
#define PL_IRQ_INTR_ID XPAR_FABRIC_CONTROLLER_CORE_0_IRQ_INTR
#elif defined(XPAR_FABRIC_CONTROLLER_CORE_0_IRQ)
#define PL_IRQ_INTR_ID XPAR_FABRIC_CONTROLLER_CORE_0_IRQ
#elif defined(XPAR_FABRIC_CONTROLLER_CORE_BD_0_IRQ_INTR)
#define PL_IRQ_INTR_ID XPAR_FABRIC_CONTROLLER_CORE_BD_0_IRQ_INTR
#else
/* Zynq-7000 IRQ_F2P[0]. Vitis SDT does not currently emit a per-IP macro for module-ref interrupts. */
#define PL_IRQ_INTR_ID 61u
#endif

static XScuGic g_interrupt_controller;
static volatile uint32_t g_pl_irq_events;

static void pl_isr(void *callback_ref)
{
    (void)callback_ref;

    uint32_t status = pl_irq_get_status();
    pl_irq_ack(status);
    g_pl_irq_events |= status;
}

static int setup_interrupts(void)
{
    XScuGic_Config *config = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (config == NULL) {
        return -1;
    }

    if (XScuGic_CfgInitialize(&g_interrupt_controller, config, config->CpuBaseAddress) != XST_SUCCESS) {
        return -1;
    }

    XScuGic_SetPriorityTriggerType(&g_interrupt_controller, PL_IRQ_INTR_ID, 0xa0u, 0x1u);

    if (XScuGic_Connect(&g_interrupt_controller, PL_IRQ_INTR_ID, pl_isr, NULL) != XST_SUCCESS) {
        return -1;
    }

    XScuGic_Enable(&g_interrupt_controller, PL_IRQ_INTR_ID);
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
                                 (Xil_ExceptionHandler)XScuGic_InterruptHandler,
                                 &g_interrupt_controller);
    Xil_ExceptionEnable();
    return 0;
}

static void wait_for_frame_ready(void)
{
    while (!pl_ready_for_frame()) {
        while (g_pl_irq_events == 0u && !pl_ready_for_frame()) {
            __asm__ volatile("wfi");
        }
        if ((g_pl_irq_events & (PL_IRQ_STATUS_UNDERRUN | PL_IRQ_STATUS_CONFIG_ERROR | PL_IRQ_STATUS_LATE_COMMIT)) != 0u) {
            xil_printf("pl irq error events=0x%08lx status=0x%08lx\r\n",
                       (unsigned long)g_pl_irq_events,
                       (unsigned long)pl_get_status());
        }
        g_pl_irq_events = 0u;
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
    pl_irq_disable();
    pl_irq_ack(0xffffffffu);
    g_pl_irq_events = 0u;
    if (setup_interrupts() != 0) {
        xil_printf("failed to set up PL interrupt\r\n");
        return -1;
    }
    pl_irq_enable(PL_IRQ_FRAME_DONE | PL_IRQ_UNDERRUN | PL_IRQ_CONFIG_ERROR | PL_IRQ_LATE_COMMIT);

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
