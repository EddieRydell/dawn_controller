#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../app/rx_packet_ring.h"

#define EXPECT_EQ(a, b) do { uint32_t av = (uint32_t)(a); uint32_t bv = (uint32_t)(b); if (av != bv) return fail_eq(__LINE__, #a, av, #b, bv); } while (0)

static int fail_eq(int line, const char *a, uint32_t av, const char *b, uint32_t bv)
{
    printf("FAIL line=%d %s=%u %s=%u\n", line, a, av, b, bv);
    return 1;
}

static int test_enqueue_dequeue_metadata(void)
{
    uint8_t payload[3] = {0x11u, 0x22u, 0x33u};
    uint8_t ip[4] = {192u, 168u, 7u, 1u};
    rx_packet_t packet;
    rx_packet_ring_status_t status;

    rx_packet_ring_init();
    EXPECT_EQ(rx_packet_ring_enqueue(payload, sizeof(payload), ip, 1234u), 0u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, 1u);
    EXPECT_EQ(status.high_water, 1u);
    EXPECT_EQ(rx_packet_ring_dequeue(&packet), 1u);
    EXPECT_EQ(packet.length, 3u);
    EXPECT_EQ(packet.payload[0], 0x11u);
    EXPECT_EQ(packet.payload[2], 0x33u);
    EXPECT_EQ(packet.source_ip[0], 192u);
    EXPECT_EQ(packet.source_ip[3], 1u);
    EXPECT_EQ(packet.received_ms, 1234u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, 0u);
    EXPECT_EQ(status.processed, 1u);
    return 0;
}

static int test_reserve_commit_metadata(void)
{
    uint8_t ip[4] = {10u, 0u, 0u, 44u};
    rx_packet_t *slot;
    rx_packet_t packet;
    rx_packet_ring_status_t status;

    rx_packet_ring_init();
    slot = rx_packet_ring_reserve();
    EXPECT_EQ(slot != NULL, 1u);
    slot->payload[0] = 0xabu;
    slot->payload[1] = 0xcdu;
    EXPECT_EQ(rx_packet_ring_commit_reserved(slot, 2u, ip, 4321u), 0u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, 1u);
    EXPECT_EQ(status.high_water, 1u);
    EXPECT_EQ(rx_packet_ring_dequeue(&packet), 1u);
    EXPECT_EQ(packet.length, 2u);
    EXPECT_EQ(packet.payload[0], 0xabu);
    EXPECT_EQ(packet.payload[1], 0xcdu);
    EXPECT_EQ(packet.source_ip[3], 44u);
    EXPECT_EQ(packet.received_ms, 4321u);
    return 0;
}

static int test_wraparound_and_full_drop_accounting(void)
{
    uint8_t payload[1] = {0u};
    rx_packet_t packet;
    rx_packet_ring_status_t status;

    rx_packet_ring_init();
    for (uint32_t i = 0u; i < RX_PACKET_RING_DEPTH; ++i) {
        payload[0] = (uint8_t)i;
        EXPECT_EQ(rx_packet_ring_enqueue(payload, sizeof(payload), NULL, i), 0u);
    }
    EXPECT_EQ(rx_packet_ring_enqueue(payload, sizeof(payload), NULL, 9999u), 1u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, RX_PACKET_RING_DEPTH);
    EXPECT_EQ(status.high_water, RX_PACKET_RING_DEPTH);
    EXPECT_EQ(status.dropped, 1u);

    for (uint32_t i = 0u; i < 17u; ++i) {
        EXPECT_EQ(rx_packet_ring_dequeue(&packet), 1u);
    }
    for (uint32_t i = 0u; i < 17u; ++i) {
        payload[0] = (uint8_t)(0xa0u + i);
        EXPECT_EQ(rx_packet_ring_enqueue(payload, sizeof(payload), NULL, 2000u + i), 0u);
    }
    for (uint32_t i = 17u; i < RX_PACKET_RING_DEPTH; ++i) {
        EXPECT_EQ(rx_packet_ring_dequeue(&packet), 1u);
        EXPECT_EQ(packet.received_ms, i);
    }
    for (uint32_t i = 0u; i < 17u; ++i) {
        EXPECT_EQ(rx_packet_ring_dequeue(&packet), 1u);
        EXPECT_EQ(packet.payload[0], (uint8_t)(0xa0u + i));
    }
    EXPECT_EQ(rx_packet_ring_dequeue(&packet), 0u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, 0u);
    EXPECT_EQ(status.processed, RX_PACKET_RING_DEPTH + 17u);
    return 0;
}

static int test_full_reserve_drop_accounting(void)
{
    rx_packet_t *slot;
    rx_packet_ring_status_t status;

    rx_packet_ring_init();
    for (uint32_t i = 0u; i < RX_PACKET_RING_DEPTH; ++i) {
        slot = rx_packet_ring_reserve();
        EXPECT_EQ(slot != NULL, 1u);
        slot->payload[0] = (uint8_t)i;
        EXPECT_EQ(rx_packet_ring_commit_reserved(slot, 1u, NULL, i), 0u);
    }
    EXPECT_EQ(rx_packet_ring_reserve() == NULL, 1u);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, RX_PACKET_RING_DEPTH);
    EXPECT_EQ(status.dropped, 1u);
    return 0;
}

static int test_oversized_rejected_without_counter_side_effect(void)
{
    uint8_t payload[RX_PACKET_RING_PAYLOAD_BYTES + 1u];
    rx_packet_ring_status_t status;

    memset(payload, 0, sizeof(payload));
    rx_packet_ring_init();
    EXPECT_EQ(rx_packet_ring_enqueue(payload, sizeof(payload), NULL, 0u), (uint32_t)-1);
    status = rx_packet_ring_status();
    EXPECT_EQ(status.depth, 0u);
    EXPECT_EQ(status.dropped, 0u);
    return 0;
}

typedef int (*test_fn)(void);

typedef struct {
    const char *name;
    test_fn fn;
} test_case_t;

int main(void)
{
    const test_case_t tests[] = {
        {"enqueue_dequeue_metadata", test_enqueue_dequeue_metadata},
        {"reserve_commit_metadata", test_reserve_commit_metadata},
        {"wraparound_and_full_drop_accounting", test_wraparound_and_full_drop_accounting},
        {"full_reserve_drop_accounting", test_full_reserve_drop_accounting},
        {"oversized_rejected_without_counter_side_effect", test_oversized_rejected_without_counter_side_effect},
    };

    for (uint32_t i = 0u; i < sizeof(tests) / sizeof(tests[0]); ++i) {
        if (tests[i].fn() != 0) {
            printf("test=%s status=fail\n", tests[i].name);
            return 1;
        }
        printf("test=%s status=ok\n", tests[i].name);
    }
    printf("rx_packet_ring_host_tests=ok count=%u\n", (unsigned int)(sizeof(tests) / sizeof(tests[0])));
    return 0;
}
