#include "pl_ingest.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#ifndef PL_BASEADDR
#if defined(XPAR_ETH_FRAME_CORE_0_BASEADDR)
#define PL_BASEADDR XPAR_ETH_FRAME_CORE_0_BASEADDR
#elif defined(XPAR_ETH_FRAME_CORE_0_S_AXI_BASEADDR)
#define PL_BASEADDR XPAR_ETH_FRAME_CORE_0_S_AXI_BASEADDR
#else
#define PL_BASEADDR 0x43C00000u
#endif
#endif

#define REG_ID              0x000u
#define REG_VERSION         0x004u
#define REG_CONTROL         0x008u
#define REG_STATUS          0x00cu
#define REG_PIN_OUT         0x010u
#define REG_FRAME_CAPACITY  0x018u
#define REG_FRAME_INDEX     0x020u
#define REG_FRAME_WORDS     0x024u
#define REG_FRAME_DATA      0x028u
#define REG_FRAME_COMMIT    0x02cu
#define REG_FRAME_COUNT     0x030u
#define REG_COMMITTED_WORDS 0x034u
#define REG_LAST_FRAME_WORD 0x038u
#define REG_ERROR_COUNT     0x03cu

#define STATUS_READY 0x00000001u
#define STATUS_OVERFLOW 0x00000002u
#define CONTROL_CLEAR_ERRORS 0x00000002u

uint32_t pl_ingest_read(uint32_t offset)
{
    return Xil_In32(PL_BASEADDR + offset);
}

void pl_ingest_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(PL_BASEADDR + offset, value);
}

void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot)
{
    snapshot->id = pl_ingest_read(REG_ID);
    snapshot->version = pl_ingest_read(REG_VERSION);
    snapshot->status = pl_ingest_read(REG_STATUS);
    snapshot->capacity_words = pl_ingest_read(REG_FRAME_CAPACITY);
    snapshot->frame_count = pl_ingest_read(REG_FRAME_COUNT);
    snapshot->committed_words = pl_ingest_read(REG_COMMITTED_WORDS);
    snapshot->error_count = pl_ingest_read(REG_ERROR_COUNT);
}

pl_ingest_result_t pl_ingest_init(uint32_t required_words)
{
    pl_ingest_snapshot_t snapshot;

    pl_ingest_snapshot(&snapshot);
    xil_printf("pl_base=0x%08lx id=0x%08lx version=0x%08lx capacity=%lu status=0x%08lx\r\n",
               (unsigned long)PL_BASEADDR,
               (unsigned long)snapshot.id,
               (unsigned long)snapshot.version,
               (unsigned long)snapshot.capacity_words,
               (unsigned long)snapshot.status);

    if (snapshot.id != PL_CORE_ID) {
        return PL_INGEST_BAD_ID;
    }
    if (snapshot.version != PL_CORE_VERSION) {
        return PL_INGEST_BAD_VERSION;
    }
    if ((snapshot.status & STATUS_READY) == 0u || (snapshot.status & STATUS_OVERFLOW) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if (snapshot.capacity_words < required_words) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    pl_ingest_write(REG_CONTROL, CONTROL_CLEAR_ERRORS);
    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_self_test(void)
{
    static const uint32_t frame[] = {
        0x00000001u,
        0x00000002u,
        0x00000004u,
        0x00000008u,
        0xdeadbeefu,
        0x12345678u,
        0x01020304u,
        0x0badc0deu,
    };

    uint32_t before = pl_ingest_read(REG_FRAME_COUNT);

    if (pl_ingest_write_frame(frame, sizeof(frame) / sizeof(frame[0])) != PL_INGEST_OK) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(REG_FRAME_COUNT) != before + 1u) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(REG_COMMITTED_WORDS) != sizeof(frame) / sizeof(frame[0])) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(REG_LAST_FRAME_WORD) != frame[7]) {
        return PL_INGEST_READBACK_FAILED;
    }

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count)
{
    uint32_t capacity = pl_ingest_read(REG_FRAME_CAPACITY);

    if (word_count > capacity) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    pl_ingest_write(REG_FRAME_INDEX, 0u);
    for (size_t i = 0u; i < word_count; ++i) {
        pl_ingest_write(REG_FRAME_DATA, words[i]);
    }

    if (pl_ingest_read(REG_FRAME_WORDS) != word_count) {
        return PL_INGEST_READBACK_FAILED;
    }

    pl_ingest_write(REG_FRAME_COMMIT, 1u);
    return PL_INGEST_OK;
}

void pl_ingest_drive_pins(uint32_t value)
{
    pl_ingest_write(REG_PIN_OUT, value & 0x0fu);
}
