#ifndef E131_PARSER_H
#define E131_PARSER_H

#include <stdint.h>

typedef enum {
    E131_PARSE_OK = 0,
    E131_PARSE_SHORT,
    E131_PARSE_ACN_ID,
    E131_PARSE_ROOT_VECTOR,
    E131_PARSE_FRAME_VECTOR,
    E131_PARSE_SYNC_VECTOR,
    E131_PARSE_DMP_VECTOR,
    E131_PARSE_DMP_ADDRESS,
    E131_PARSE_PROP_COUNT,
    E131_PARSE_START_CODE,
    E131_PARSE_UNIVERSE,
} e131_parse_result_t;

typedef struct {
    const uint8_t *cid;
    uint8_t priority;
    uint16_t universe;
    uint8_t sequence;
    uint8_t options;
    uint16_t sync_address;
    const uint8_t *rgb_slots;
    uint16_t rgb_slot_count;
    uint32_t first_linear_pixel;
    uint32_t rgb_pixel_count;
} e131_data_packet_t;

typedef struct {
    const uint8_t *cid;
    uint8_t sequence;
    uint16_t sync_address;
} e131_sync_packet_t;

const char *e131_parse_result_name(e131_parse_result_t result);
e131_parse_result_t e131_parse_data_packet(const uint8_t *data,
                                           uint16_t length,
                                           uint16_t first_universe,
                                           uint32_t total_pixels,
                                           e131_data_packet_t *packet);
e131_parse_result_t e131_parse_sync_packet(const uint8_t *data,
                                           uint16_t length,
                                           e131_sync_packet_t *packet);

#endif
