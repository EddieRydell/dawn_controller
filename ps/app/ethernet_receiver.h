#ifndef ETHERNET_RECEIVER_H
#define ETHERNET_RECEIVER_H

#include <stdint.h>

typedef struct {
    uint32_t rx_packets;
    uint32_t rx_bytes;
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
    uint32_t last_packet_gap_ms;
    uint32_t max_packet_gap_ms;
    uint32_t last_frame_commit_gap_ms;
    uint32_t max_frame_commit_gap_ms;
    uint16_t last_universe;
    uint8_t last_sequence;
    const char *last_error;
    uint8_t link_up;
} ethernet_receiver_counters_t;

int ethernet_receiver_init(void);
void ethernet_receiver_poll(void);
uint32_t ethernet_receiver_now_ms(void);
const ethernet_receiver_counters_t *ethernet_receiver_counters(void);
void ethernet_receiver_print_status(void);

#endif
