#include "pl_ingest.h"

#include "xil_io.h"
#include "xil_printf.h"
#include "xparameters.h"

#if defined(XPAR_ETH_CONTROL_CORE_0_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_ETH_CONTROL_CORE_0_BASEADDR
#elif defined(XPAR_ETH_CONTROL_CORE_0_S_AXI_BASEADDR)
#define PL_CONTROL_BASEADDR XPAR_ETH_CONTROL_CORE_0_S_AXI_BASEADDR
#else
#error "Missing ETH_CONTROL_CORE_0 base address in xparameters.h"
#endif

#if defined(XPAR_AXIL_FRAME_RAM_0_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_BASEADDR
#elif defined(XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR)
#define PL_FRAME_BASEADDR XPAR_AXIL_FRAME_RAM_0_S_AXI_BASEADDR
#else
#error "Missing AXIL_FRAME_RAM_0 base address in xparameters.h"
#endif

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

static uint32_t expected_next(uint32_t value)
{
    return value + 1u;
}

void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot)
{
    snapshot->id = pl_ingest_read(PL_REG_ID);
    snapshot->version = pl_ingest_read(PL_REG_VERSION);
    snapshot->status = pl_ingest_read(PL_REG_STATUS);
    snapshot->capacity_words = pl_ingest_read(PL_REG_FRAME_CAPACITY);
    snapshot->bank_words = pl_ingest_read(PL_REG_FRAME_BANK_WORDS);
    snapshot->active_bank = pl_ingest_read(PL_REG_ACTIVE_BANK);
    snapshot->write_bank = pl_ingest_read(PL_REG_WRITE_BANK);
    snapshot->frame_sequence = pl_ingest_read(PL_REG_FRAME_SEQUENCE);
    snapshot->frame_count = pl_ingest_read(PL_REG_FRAME_COUNT);
    snapshot->committed_words = pl_ingest_read(PL_REG_COMMITTED_WORDS);
    snapshot->error_count = pl_ingest_read(PL_REG_ERROR_COUNT);
    snapshot->consumer_status = pl_ingest_read(PL_REG_CONSUMER_STATUS);
    snapshot->consumer_sequence = pl_ingest_read(PL_REG_CONSUMER_SEQUENCE);
    snapshot->consumer_frame_count = pl_ingest_read(PL_REG_CONSUMER_FRAME_COUNT);
    snapshot->consumer_error_count = pl_ingest_read(PL_REG_CONSUMER_ERROR_COUNT);
}

pl_ingest_result_t pl_ingest_init(uint32_t required_words)
{
    pl_ingest_snapshot_t snapshot;

    pl_ingest_snapshot(&snapshot);
    xil_printf("pl_control=0x%08lx pl_frame=0x%08lx id=0x%08lx version=0x%08lx capacity=%lu bank_words=%lu active_bank=%lu write_bank=%lu status=0x%08lx consumer_status=0x%08lx\r\n",
               (unsigned long)PL_CONTROL_BASEADDR,
               (unsigned long)PL_FRAME_BASEADDR,
               (unsigned long)snapshot.id,
               (unsigned long)snapshot.version,
               (unsigned long)snapshot.capacity_words,
               (unsigned long)snapshot.bank_words,
               (unsigned long)snapshot.active_bank,
               (unsigned long)snapshot.write_bank,
               (unsigned long)snapshot.status,
               (unsigned long)snapshot.consumer_status);

    if (PL_CONTROL_BASEADDR != PL_CONTROL_EXPECTED_BASEADDR || PL_FRAME_BASEADDR != PL_FRAME_EXPECTED_BASEADDR) {
        return PL_INGEST_BAD_PLATFORM;
    }
    if (snapshot.id != PL_CORE_ID) {
        return PL_INGEST_BAD_ID;
    }
    if (snapshot.version != PL_CORE_VERSION) {
        return PL_INGEST_BAD_VERSION;
    }
    if ((snapshot.status & PL_STATUS_READY) == 0u
        || (snapshot.status & (PL_STATUS_OVERFLOW | PL_STATUS_CONSUMER_ERROR)) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if (snapshot.bank_words < required_words) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    pl_ingest_write(PL_REG_CONTROL, PL_CONTROL_CLEAR_ERRORS);
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

    uint32_t before = pl_ingest_read(PL_REG_FRAME_COUNT);

    if (pl_ingest_write_frame(frame, sizeof(frame) / sizeof(frame[0])) != PL_INGEST_OK) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_REG_FRAME_COUNT) != before + 1u) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_REG_COMMITTED_WORDS) != sizeof(frame) / sizeof(frame[0])) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_REG_ACTIVE_BANK) > 1u || pl_ingest_read(PL_REG_WRITE_BANK) > 1u) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (pl_ingest_read(PL_REG_LAST_FRAME_WORD) != frame[7]) {
        return PL_INGEST_READBACK_FAILED;
    }

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count)
{
    pl_ingest_snapshot_t before;
    pl_ingest_snapshot_t after;
    uint32_t bank_words;
    uint32_t write_bank;
    size_t bank_offset;
    uint32_t commit_value;

    if (words == NULL && word_count > 0u) {
        return PL_INGEST_BAD_ARGUMENT;
    }

    pl_ingest_snapshot(&before);
    bank_words = before.bank_words;
    write_bank = before.write_bank;
    bank_offset = (size_t)write_bank * (size_t)bank_words;

    if ((before.status & PL_STATUS_READY) == 0u
        || (before.status & (PL_STATUS_OVERFLOW | PL_STATUS_CONSUMER_ERROR)) != 0u) {
        return PL_INGEST_BAD_STATUS;
    }
    if (write_bank > 1u || word_count > bank_words || word_count > PL_FRAME_COMMIT_WORD_MASK) {
        return PL_INGEST_CAPACITY_TOO_SMALL;
    }

    for (size_t i = 0u; i < word_count; ++i) {
        pl_frame_write_word(bank_offset + i, words[i]);
    }

    if (word_count > 0u) {
        pl_ingest_write(PL_REG_FIRST_FRAME_WORD, words[0]);
        pl_ingest_write(PL_REG_LAST_FRAME_WORD, words[word_count - 1u]);
    } else {
        pl_ingest_write(PL_REG_FIRST_FRAME_WORD, 0u);
        pl_ingest_write(PL_REG_LAST_FRAME_WORD, 0u);
    }

    if (word_count > 0u && pl_frame_read_word(bank_offset) != words[0]) {
        return PL_INGEST_READBACK_FAILED;
    }
    if (word_count > 1u && pl_frame_read_word(bank_offset + word_count - 1u) != words[word_count - 1u]) {
        return PL_INGEST_READBACK_FAILED;
    }

    commit_value = (write_bank << PL_FRAME_COMMIT_BANK_SHIFT) | (uint32_t)word_count;
    pl_ingest_write(PL_REG_FRAME_COMMIT, commit_value);

    pl_ingest_snapshot(&after);
    if (after.frame_count != expected_next(before.frame_count)
        || after.frame_sequence != expected_next(before.frame_sequence)
        || after.active_bank != write_bank
        || after.write_bank != (write_bank ^ 1u)
        || after.committed_words != word_count
        || (after.status & PL_STATUS_READY) == 0u
        || (after.status & (PL_STATUS_OVERFLOW | PL_STATUS_CONSUMER_ERROR)) != 0u) {
        return PL_INGEST_COMMIT_FAILED;
    }

    return PL_INGEST_OK;
}

pl_ingest_result_t pl_ingest_enable_consumer(void)
{
    uint32_t consumer_status;

    pl_ingest_write(PL_REG_CONSUMER_CONTROL, PL_CONSUMER_RESET);
    pl_ingest_write(PL_REG_CONTROL, PL_CONTROL_CLEAR_ERRORS);
    pl_ingest_write(PL_REG_CONSUMER_CONTROL, PL_CONSUMER_ENABLE);

    consumer_status = pl_ingest_read(PL_REG_CONSUMER_STATUS);
    if ((consumer_status & PL_CONSUMER_STATUS_ENABLED) == 0u
        || (consumer_status & PL_CONSUMER_STATUS_ERROR) != 0u) {
        return PL_INGEST_CONSUMER_FAILED;
    }

    return PL_INGEST_OK;
}

void pl_ingest_drive_pins(uint32_t value)
{
    pl_ingest_write(PL_REG_PIN_OUT, value & 0x0fu);
}
