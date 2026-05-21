#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "../app/app_config.h"
#include "../app/e131_parser.h"
#include "../app/e131_receiver.h"
#include "../app/frame_pipeline.h"

#define MAX_PACKET 638u
#define EXPECT_TRUE(expr) do { if (!(expr)) return fail(__LINE__, #expr); } while (0)
#define EXPECT_EQ(a, b) do { uint32_t av = (uint32_t)(a); uint32_t bv = (uint32_t)(b); if (av != bv) return fail_eq(__LINE__, #a, av, #b, bv); } while (0)

static uint32_t g_commit_count;
static uint32_t g_write_count;
static uint32_t g_clear_count;
static int g_commit_result;
static uint32_t g_words[DAWN_WORDS_PER_FRAME];

uint32_t *frame_pipeline_inactive_words(void)
{
    return g_words;
}

uint32_t frame_pipeline_active_pixel_count(void)
{
    return DAWN_WORDS_PER_FRAME;
}

void frame_pipeline_init(void)
{
}

void frame_pipeline_clear_all(uint32_t rgb_word)
{
    g_clear_count++;
    for (uint32_t i = 0u; i < DAWN_WORDS_PER_FRAME; ++i) {
        g_words[i] = rgb_word & 0x00ffffffu;
    }
}

int frame_pipeline_write_linear_rgb(uint32_t first_pixel, const uint8_t *rgb_slots, uint32_t rgb_pixel_count)
{
    (void)first_pixel;
    (void)rgb_slots;
    (void)rgb_pixel_count;
    g_write_count++;
    return 0;
}

int frame_pipeline_commit(void)
{
    if (g_commit_result != 0) {
        return g_commit_result;
    }
    g_commit_count++;
    return 0;
}

int frame_pipeline_configure(uint32_t active_count, const uint32_t lengths[4])
{
    (void)active_count;
    (void)lengths;
    return 0;
}

static int fail(int line, const char *expr)
{
    printf("FAIL line=%d expr=%s\n", line, expr);
    return 1;
}

static int fail_eq(int line, const char *a, uint32_t av, const char *b, uint32_t bv)
{
    printf("FAIL line=%d %s=%u %s=%u\n", line, a, av, b, bv);
    return 1;
}

static void reset_receiver(void)
{
    g_commit_count = 0u;
    g_write_count = 0u;
    g_clear_count = 0u;
    g_commit_result = 0;
    e131_receiver_init();
}

static uint16_t flags_and_length(uint16_t length)
{
    return (uint16_t)(0x7000u | length);
}

static void put16(uint8_t *p, uint16_t v)
{
    p[0] = (uint8_t)(v >> 8);
    p[1] = (uint8_t)v;
}

static void put32(uint8_t *p, uint32_t v)
{
    p[0] = (uint8_t)(v >> 24);
    p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);
    p[3] = (uint8_t)v;
}

static uint16_t build_data(uint8_t *packet,
                           uint16_t universe,
                           uint8_t sequence,
                           const uint8_t cid[16],
                           uint8_t priority,
                           uint16_t sync_address,
                           uint8_t options,
                           uint16_t slot_count)
{
    uint16_t total_len = (uint16_t)(126u + slot_count);

    memset(packet, 0, total_len);
    put16(&packet[0], 0x0010u);
    put16(&packet[2], 0u);
    memcpy(&packet[4], "ASC-E1.17\0\0\0", 12u);
    put16(&packet[16], flags_and_length((uint16_t)(total_len - 16u)));
    put32(&packet[18], 0x00000004u);
    memcpy(&packet[22], cid, 16u);
    put16(&packet[38], flags_and_length((uint16_t)(total_len - 38u)));
    put32(&packet[40], 0x00000002u);
    memcpy(&packet[44], "host-test", 9u);
    packet[108] = priority;
    put16(&packet[109], sync_address);
    packet[111] = sequence;
    packet[112] = options;
    put16(&packet[113], universe);
    put16(&packet[115], flags_and_length((uint16_t)(total_len - 115u)));
    packet[117] = 0x02u;
    packet[118] = 0xa1u;
    put16(&packet[119], 0u);
    put16(&packet[121], 1u);
    put16(&packet[123], (uint16_t)(slot_count + 1u));
    packet[125] = 0u;
    for (uint16_t i = 0u; i < slot_count; ++i) {
        packet[126u + i] = (uint8_t)i;
    }
    return total_len;
}

static uint16_t build_sync(uint8_t *packet, uint8_t sequence, const uint8_t cid[16], uint16_t sync_address)
{
    uint16_t total_len = 49u;

    memset(packet, 0, total_len);
    put16(&packet[0], 0x0010u);
    put16(&packet[2], 0u);
    memcpy(&packet[4], "ASC-E1.17\0\0\0", 12u);
    put16(&packet[16], flags_and_length((uint16_t)(total_len - 16u)));
    put32(&packet[18], 0x00000008u);
    memcpy(&packet[22], cid, 16u);
    put16(&packet[38], flags_and_length((uint16_t)(total_len - 38u)));
    put32(&packet[40], 0x00000001u);
    packet[44] = sequence;
    put16(&packet[45], sync_address);
    put16(&packet[47], 0u);
    return total_len;
}

static uint16_t slots_for_offset(uint32_t offset)
{
    uint32_t first_slot = offset * DAWN_SLOTS_PER_UNIVERSE;
    uint32_t remaining = (DAWN_WORDS_PER_FRAME * 3u) - first_slot;
    return (uint16_t)(remaining > DAWN_SLOTS_PER_UNIVERSE ? DAWN_SLOTS_PER_UNIVERSE : remaining);
}

static void send_universe(uint32_t offset, uint8_t sequence, const uint8_t cid[16], uint8_t priority, uint16_t sync_address, uint8_t options, uint32_t now_ms)
{
    uint8_t packet[MAX_PACKET];
    uint8_t ip[4] = {192u, 168u, 7u, 1u};
    uint16_t length = build_data(packet,
                                 (uint16_t)(DAWN_FIRST_UNIVERSE + offset),
                                 sequence,
                                 cid,
                                 priority,
                                 sync_address,
                                 options,
                                 slots_for_offset(offset));
    e131_receiver_handle_packet(packet, length, ip, now_ms);
}

static int test_parser_rejects(void)
{
    uint8_t packet[MAX_PACKET];
    uint8_t cid[16] = {1u};
    e131_data_packet_t parsed;
    uint16_t len = build_data(packet, DAWN_FIRST_UNIVERSE, 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);

    EXPECT_EQ(e131_parse_data_packet(packet, 10u, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_SHORT);
    packet[4] = 0u;
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_ACN_ID);
    len = build_data(packet, DAWN_FIRST_UNIVERSE, 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    put32(&packet[18], 0u);
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_ROOT_VECTOR);
    len = build_data(packet, DAWN_FIRST_UNIVERSE, 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    put32(&packet[40], 0u);
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_FRAME_VECTOR);
    len = build_data(packet, DAWN_FIRST_UNIVERSE, 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    packet[117] = 0u;
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_DMP_VECTOR);
    len = build_data(packet, DAWN_FIRST_UNIVERSE, 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    packet[125] = 1u;
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_START_CODE);
    len = build_data(packet, (uint16_t)(DAWN_FIRST_UNIVERSE - 1u), 7u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_UNIVERSE);
    return 0;
}

static int test_parser_metadata(void)
{
    uint8_t packet[MAX_PACKET];
    uint8_t cid[16] = {0xdeu, 0xadu, 0xbeu, 0xefu};
    e131_data_packet_t parsed;
    uint16_t len = build_data(packet, 3u, 42u, cid, 150u, 63999u, 0x80u, DAWN_SLOTS_PER_UNIVERSE);

    EXPECT_EQ(e131_parse_data_packet(packet, len, DAWN_FIRST_UNIVERSE, DAWN_WORDS_PER_FRAME, &parsed), E131_PARSE_OK);
    EXPECT_EQ(parsed.cid[0], 0xdeu);
    EXPECT_EQ(parsed.priority, 150u);
    EXPECT_EQ(parsed.sync_address, 63999u);
    EXPECT_EQ(parsed.sequence, 42u);
    EXPECT_EQ(parsed.options, 0x80u);
    EXPECT_EQ(parsed.universe, 3u);
    EXPECT_EQ(parsed.rgb_slot_count, DAWN_SLOTS_PER_UNIVERSE);
    EXPECT_TRUE(parsed.rgb_slots == &packet[126]);
    return 0;
}

static int test_unsynced_out_of_order_commits_once(void)
{
    uint8_t cid[16] = {1u};

    reset_receiver();
    for (int32_t offset = 24; offset >= 0; --offset) {
        send_universe((uint32_t)offset, (uint8_t)offset, cid, 100u, 0u, 0u, 0u);
    }
    EXPECT_EQ(g_commit_count, 1u);
    EXPECT_EQ(e131_receiver_status()->complete_frames, 1u);
    EXPECT_EQ(e131_receiver_status()->universes_seen, 25u);
    return 0;
}

static int test_exact_final_slot_count(void)
{
    uint8_t packet[MAX_PACKET];
    uint8_t ip[4] = {1u, 2u, 3u, 4u};
    uint8_t cid[16] = {2u};
    uint16_t len;

    reset_receiver();
    len = build_data(packet, (uint16_t)(DAWN_FIRST_UNIVERSE + 24u), 1u, cid, 100u, 0u, 0u, DAWN_SLOTS_PER_UNIVERSE);
    e131_receiver_handle_packet(packet, len, ip, 0u);
    EXPECT_EQ(e131_receiver_status()->e131_rejected, 1u);
    EXPECT_EQ(g_write_count, 0u);
    return 0;
}

static int test_missing_universe_blackout(void)
{
    uint8_t cid[16] = {3u};

    reset_receiver();
    for (uint32_t offset = 0u; offset < 24u; ++offset) {
        send_universe(offset, (uint8_t)offset, cid, 100u, 0u, 0u, 0u);
    }
    e131_receiver_poll(499u);
    EXPECT_EQ(e131_receiver_status()->blackouts, 0u);
    e131_receiver_poll(500u);
    EXPECT_EQ(e131_receiver_status()->blackouts, 1u);
    EXPECT_EQ(e131_receiver_status()->incomplete_sweeps, 1u);
    EXPECT_EQ(e131_receiver_status()->source_locked, 0u);
    return 0;
}

static int test_synced_waits_for_sync(void)
{
    uint8_t packet[MAX_PACKET];
    uint8_t ip[4] = {192u, 168u, 7u, 1u};
    uint8_t cid[16] = {4u};
    uint16_t len;

    reset_receiver();
    for (uint32_t offset = 0u; offset < 25u; ++offset) {
        send_universe(offset, (uint8_t)offset, cid, 100u, DAWN_E131_DEFAULT_SYNC_ADDRESS, 0u, 0u);
    }
    EXPECT_EQ(g_commit_count, 0u);
    EXPECT_EQ(e131_receiver_status()->sync_waits, 1u);
    len = build_sync(packet, 1u, cid, DAWN_E131_DEFAULT_SYNC_ADDRESS);
    e131_receiver_handle_packet(packet, len, ip, 10u);
    EXPECT_EQ(g_commit_count, 1u);
    EXPECT_EQ(e131_receiver_status()->complete_frames, 1u);
    return 0;
}

static int test_missing_sync_blackout(void)
{
    uint8_t cid[16] = {5u};

    reset_receiver();
    for (uint32_t offset = 0u; offset < 25u; ++offset) {
        send_universe(offset, (uint8_t)offset, cid, 100u, DAWN_E131_DEFAULT_SYNC_ADDRESS, 0u, 0u);
    }
    e131_receiver_poll(500u);
    EXPECT_EQ(e131_receiver_status()->blackouts, 1u);
    EXPECT_EQ(e131_receiver_status()->sync_timeouts, 1u);
    return 0;
}

static int test_priority_policy(void)
{
    uint8_t cid_a[16] = {0x0au};
    uint8_t cid_b[16] = {0x0bu};

    reset_receiver();
    send_universe(0u, 1u, cid_a, 100u, 0u, 0u, 0u);
    send_universe(0u, 1u, cid_b, 100u, 0u, 0u, 1u);
    EXPECT_EQ(e131_receiver_status()->ignored_sources, 1u);
    EXPECT_EQ(e131_receiver_status()->active_priority, 100u);
    send_universe(0u, 1u, cid_b, 101u, 0u, 0u, 2u);
    EXPECT_EQ(e131_receiver_status()->active_priority, 101u);
    EXPECT_EQ(e131_receiver_status()->ignored_sources, 1u);
    return 0;
}

static int test_preview_rejected(void)
{
    uint8_t cid[16] = {6u};

    reset_receiver();
    send_universe(0u, 1u, cid, 100u, 0u, 0x80u, 0u);
    EXPECT_EQ(e131_receiver_status()->preview_rejects, 1u);
    EXPECT_EQ(e131_receiver_status()->e131_rejected, 1u);
    EXPECT_EQ(g_write_count, 0u);
    return 0;
}

static int test_stream_terminated_blacks(void)
{
    uint8_t cid[16] = {7u};

    reset_receiver();
    send_universe(0u, 1u, cid, 100u, 0u, 0x40u, 0u);
    EXPECT_EQ(e131_receiver_status()->blackouts, 1u);
    EXPECT_EQ(e131_receiver_status()->source_locked, 0u);
    EXPECT_EQ(g_clear_count, 1u);
    return 0;
}

static int test_fuzz_no_commit(void)
{
    uint8_t packet[MAX_PACKET];
    uint32_t state = 0x12345678u;

    reset_receiver();
    for (uint32_t i = 0u; i < 200u; ++i) {
        uint16_t len;
        state = state * 1664525u + 1013904223u;
        len = (uint16_t)(state % MAX_PACKET);
        for (uint16_t j = 0u; j < len; ++j) {
            state = state * 1664525u + 1013904223u;
            packet[j] = (uint8_t)(state >> 24);
        }
        e131_receiver_handle_packet(packet, len, NULL, i);
    }
    EXPECT_EQ(g_commit_count, 0u);
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
        {"parser_rejects", test_parser_rejects},
        {"parser_metadata", test_parser_metadata},
        {"unsynced_out_of_order_commits_once", test_unsynced_out_of_order_commits_once},
        {"exact_final_slot_count", test_exact_final_slot_count},
        {"missing_universe_blackout", test_missing_universe_blackout},
        {"synced_waits_for_sync", test_synced_waits_for_sync},
        {"missing_sync_blackout", test_missing_sync_blackout},
        {"priority_policy", test_priority_policy},
        {"preview_rejected", test_preview_rejected},
        {"stream_terminated_blacks", test_stream_terminated_blacks},
        {"fuzz_no_commit", test_fuzz_no_commit},
    };

    for (uint32_t i = 0u; i < sizeof(tests) / sizeof(tests[0]); ++i) {
        if (tests[i].fn() != 0) {
            printf("test=%s status=fail\n", tests[i].name);
            return 1;
        }
        printf("test=%s status=ok\n", tests[i].name);
    }
    printf("ps_host_tests=ok count=%u\n", (unsigned int)(sizeof(tests) / sizeof(tests[0])));
    return 0;
}
