#include "pl_ingest.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#ifndef PL_CONTROL_BASEADDR
#if defined(XPAR_ETH_CONTROL_CORE_0_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_ETH_CONTROL_CORE_0_BASEADDR
#elif defined(XPAR_ETH_CONTROL_CORE_0_S_AXI_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_ETH_CONTROL_CORE_0_S_AXI_BASEADDR
#else
#define PL_CONTROL_BASEADDR 0x43C00000u
#endif
#endif

#ifndef PL_FRAME_BASEADDR
#if defined(XPAR_AXIL_FRAME_RAM_0_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_BASEADDR
#elif defined(XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR
#else
#define PL_FRAME_BASEADDR 0x43C10000u
#endif
#endif

#define REG_ID               0x000u
#define REG_VERSION          0x004u
#define REG_CONTROL          0x008u
#define REG_STATUS           0x00cu
#define REG_PIN_OUT          0x010u
#define REG_FRAME_CAPACITY   0x018u
#define REG_FRAME_COMMIT     0x020u
#define REG_FRAME_COUNT      0x024u
#define REG_COMMITTED_WORDS  0x028u
#define REG_FIRST_FRAME_WORD 0x02cu
#define REG_LAST_FRAME_WORD  0x030u
#define REG_ERROR_COUNT      0x034u

#define STATUS_READY 0x00000001u
#define STATUS_OVERFLOW 0x00000002u
#define CONTROL_CLEAR_ERRORS 0x00000002u

uint32_t pl_ingest_read(uint32_t offset)
{
    return Xil_In32(PL_CONTROL_BASEADDR + offset);
}

void pl_ingest_write(uint32_t offset, uint32_t value)
{
    Xil_Out32(PL_CONTROL_BASEADDR + offset, value);
}

static uint32_t pl_frame_read_word(size_t index)
{
    return Xil_In32(PL_FRAME_BASEADDR + (uint32_t)(index * sizeof(uint32_t)));
}

static void pl_frame_write_word(size_t index, uint32_t value)
{
    Xil_Out32(PL_FRAME_BASEADDR + (uint32_t)(index * sizeof(uint32_t)), value);
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
    xil_printf("pl_control=0x%08lx pl_frame=0x%08lx id=0x%08lx version=0x%08lx capacity=%lu status=0x%08lx\r\n",
               (unsigned long)PL_CONTROL_BASEADDR,
               (unsigned long)PL_FRAME_BASEADDR,
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

    for (size_t i = 0u; i < word_count; ++i) {
        pl_frame_write_word(i, words[i]);
    }

    if (word_count > 0u) {
        pl_ingest_write(REG_FIRST_FRAME_WORD, words[0]);
        pl_ingest_write(REG_LAST_FRAME_WORD, words[word_count - 1u]);
    } else {
        pl_ingest_write(REG_FIRST_FRAME_WORD, 0u);
        pl_ingest_write(REG_LAST_FRAME_WORD, 0u);
    }

    if (word_count > 0u && pl_frame_read_word(0u) != words[0]) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (word_count > 1u && pl_frame_read_word(word_count - 1u) != words[word_count - 1u]) {
        return PL_INGEST_READBACK_FAILED;
    }

    pl_ingest_write(REG_FRAME_COMMIT, (uint32_t)word_count);
    return PL_INGEST_OK;
}

void pl_ingest_drive_pins(uint32_t value)
{
    pl_ingest_write(REG_PIN_OUT, value & 0x0fu);
}
