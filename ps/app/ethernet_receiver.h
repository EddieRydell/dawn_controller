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
    uint16_t last_universe;
    uint8_t last_sequence;
    const char *last_error;
    uint8_t link_up;
} ethernet_receiver_counters_t;

int ethernet_receiver_init(void);
void ethernet_receiver_poll(void);
const ethernet_receiver_counters_t *ethernet_receiver_counters(void);
void ethernet_receiver_print_status(void);

#endif
