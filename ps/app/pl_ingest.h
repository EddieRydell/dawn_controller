#ifndef PL_INGEST_H
#define PL_INGEST_H

#include <stddef.h>
#include <stdint.h>

#define PL_CORE_ID 0x4546504cu
#define PL_CORE_VERSION 0x00010000u

typedef enum {
    PL_INGEST_OK = 0,
    PL_INGEST_BAD_ID = -1,
    PL_INGEST_BAD_VERSION = -2,
    PL_INGEST_BAD_STATUS = -3,
    PL_INGEST_CAPACITY_TOO_SMALL = -4,
    PL_INGEST_READBACK_FAILED = -5,
} pl_ingest_result_t;

typedef struct {
    uint32_t id;
    uint32_t version;
    uint32_t status;
    uint32_t capacity_words;
    uint32_t frame_count;
    uint32_t committed_words;
    uint32_t error_count;
} pl_ingest_snapshot_t;

uint32_t pl_ingest_read(uint32_t offset);
void pl_ingest_write(uint32_t offset, uint32_t value);
void pl_ingest_snapshot(pl_ingest_snapshot_t *snapshot);
pl_ingest_result_t pl_ingest_init(uint32_t required_words);
pl_ingest_result_t pl_ingest_self_test(void);
pl_ingest_result_t pl_ingest_write_frame(const uint32_t *words, size_t word_count);
void pl_ingest_drive_pins(uint32_t value);

#endif
