#ifndef PL_CONTRACT_H
#define PL_CONTRACT_H

#include <stdint.h>

#define PL_CORE_ID 0x4546504cu
#define PL_CORE_VERSION 0x00030000u

#define PL_CONTROL_EXPECTED_BASEADDR 0x43c00000u
#define PL_CONTROL_EXPECTED_HIGHADDR 0x43c00fffu
#define PL_FRAME_EXPECTED_BASEADDR 0x43c10000u
#define PL_FRAME_EXPECTED_HIGHADDR 0x43c17fffu

#define PL_REG_ID                         0x000u
#define PL_REG_VERSION                    0x004u
#define PL_REG_CONTROL                    0x008u
#define PL_REG_STATUS                     0x00cu
#define PL_REG_PIN_OUT                    0x010u
#define PL_REG_COUNTER                    0x014u
#define PL_REG_FRAME_CAPACITY             0x018u
#define PL_REG_FRAME_COMMIT               0x020u
#define PL_REG_FRAME_COUNT                0x024u
#define PL_REG_COMMITTED_WORDS            0x028u
#define PL_REG_FIRST_FRAME_WORD           0x02cu
#define PL_REG_LAST_FRAME_WORD            0x030u
#define PL_REG_ERROR_COUNT                0x034u
#define PL_REG_FRAME_BANK_WORDS           0x038u
#define PL_REG_ACTIVE_BANK                0x03cu
#define PL_REG_WRITE_BANK                 0x040u
#define PL_REG_FRAME_SEQUENCE             0x044u
#define PL_REG_CONSUMER_CONTROL           0x048u
#define PL_REG_CONSUMER_STATUS            0x04cu
#define PL_REG_CONSUMER_SEQUENCE          0x050u
#define PL_REG_CONSUMER_FRAME_COUNT       0x054u
#define PL_REG_CONSUMER_ERROR_COUNT       0x058u
#define PL_REG_WS281X_BIT_RATE            0x05cu
#define PL_REG_WS281X_OUTPUT_COUNT        0x060u
#define PL_REG_WS281X_PIXELS_PER_OUTPUT   0x064u
#define PL_REG_CONSUMER_DEBUG             0x068u

#define PL_STATUS_READY          0x00000001u
#define PL_STATUS_OVERFLOW       0x00000002u
#define PL_STATUS_CONSUMER_ERROR 0x00000004u

#define PL_CONTROL_CLEAR_ERRORS 0x00000002u

#define PL_CONSUMER_ENABLE 0x00000001u
#define PL_CONSUMER_RESET  0x00000002u

#define PL_CONSUMER_STATUS_ENABLED   0x00000001u
#define PL_CONSUMER_STATUS_BUSY      0x00000002u
#define PL_CONSUMER_STATUS_RESET_LOW 0x00000004u
#define PL_CONSUMER_STATUS_ERROR     0x00000008u

#define PL_FRAME_COMMIT_BANK_SHIFT 31u
#define PL_FRAME_COMMIT_WORD_MASK 0x7fffffffu

#endif
