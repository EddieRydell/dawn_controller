#ifndef E131_RECEIVER_H
#define E131_RECEIVER_H

#include <stdint.h>

typedef struct {
    uint32_t e131_valid;
    uint32_t e131_rejected;
    uint32_t universes_seen;
    uint32_t frames_committed;
    uint32_t frames_dropped;
    uint32_t complete_frames;
    uint32_t incomplete_sweeps;
    uint32_t ignored_sources;
    uint32_t sequence_anomalies;
    uint32_t preview_rejects;
    uint32_t sync_waits;
    uint32_t sync_timeouts;
    uint32_t blackouts;
    uint16_t last_universe;
    uint8_t last_sequence;
    const char *last_error;
    uint8_t source_locked;
    uint8_t active_priority;
    uint8_t sync_mode;
    uint16_t sync_address;
    uint8_t source_ip[4];
} e131_receiver_status_t;

void e131_receiver_init(void);
void e131_receiver_handle_packet(const uint8_t *data,
                                 uint16_t length,
                                 const uint8_t source_ip[4],
                                 uint32_t now_ms);
void e131_receiver_poll(uint32_t now_ms);
const e131_receiver_status_t *e131_receiver_status(void);

#endif
