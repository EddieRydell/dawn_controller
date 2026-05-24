#include "rx_packet_ring.h"

#include <stddef.h>
#include <string.h>

static rx_packet_t g_slots[RX_PACKET_RING_DEPTH];
static uint32_t g_head;
static uint32_t g_tail;
static uint32_t g_depth;
static uint32_t g_high_water;
static uint32_t g_dropped;
static uint32_t g_processed;

void rx_packet_ring_init(void)
{
    g_head = 0u;
    g_tail = 0u;
    g_depth = 0u;
    g_high_water = 0u;
    g_dropped = 0u;
    g_processed = 0u;
}

rx_packet_t *rx_packet_ring_reserve(void)
{
    if (g_depth == RX_PACKET_RING_DEPTH) {
        g_dropped++;
        return NULL;
    }

    return &g_slots[g_head];
}

int rx_packet_ring_commit_reserved(rx_packet_t *slot,
                                   uint16_t length,
                                   const uint8_t source_ip[4],
                                   uint32_t received_ms)
{
    if (slot == NULL || slot != &g_slots[g_head] || length > RX_PACKET_RING_PAYLOAD_BYTES) {
        return -1;
    }

    slot->length = length;
    slot->received_ms = received_ms;
    for (uint32_t i = 0u; i < 4u; ++i) {
        slot->source_ip[i] = source_ip != NULL ? source_ip[i] : 0u;
    }

    g_head = (g_head + 1u) % RX_PACKET_RING_DEPTH;
    g_depth++;
    if (g_depth > g_high_water) {
        g_high_water = g_depth;
    }
    return 0;
}

int rx_packet_ring_enqueue(const uint8_t *payload,
                           uint16_t length,
                           const uint8_t source_ip[4],
                           uint32_t received_ms)
{
    rx_packet_t *slot;

    if (payload == NULL || length > RX_PACKET_RING_PAYLOAD_BYTES) {
        return -1;
    }

    slot = rx_packet_ring_reserve();
    if (slot == NULL) {
        return 1;
    }

    memcpy(slot->payload, payload, length);
    return rx_packet_ring_commit_reserved(slot, length, source_ip, received_ms);
}

int rx_packet_ring_dequeue(rx_packet_t *packet)
{
    if (packet == NULL || g_depth == 0u) {
        return 0;
    }

    *packet = g_slots[g_tail];
    g_tail = (g_tail + 1u) % RX_PACKET_RING_DEPTH;
    g_depth--;
    g_processed++;
    return 1;
}

rx_packet_ring_status_t rx_packet_ring_status(void)
{
    rx_packet_ring_status_t status;

    status.depth = g_depth;
    status.high_water = g_high_water;
    status.dropped = g_dropped;
    status.processed = g_processed;
    return status;
}
