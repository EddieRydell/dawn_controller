/* Generated from memory_map.yaml. Do not edit by hand. */
#ifndef PL_REGS_H
#define PL_REGS_H

#include <stdint.h>

#define PL_REG_CONTROL                        0x000u
#define PL_ENABLE                              (1u << 0)
#define PL_COMMIT_FRAME                        (1u << 1)

#define PL_REG_STATUS                         0x004u
#define PL_BUSY                                (1u << 0)
#define PL_FRAME_PENDING                       (1u << 1)
#define PL_UNDERRUN                            (1u << 2)
#define PL_CONFIG_ERROR                        (1u << 3)
#define PL_READY_FOR_FRAME                     (1u << 4)

#define PL_REG_ACTIVE_BANK                    0x008u

#define PL_REG_WRITE_BANK                     0x00cu

#define PL_REG_FRAME_COUNTER                  0x010u

#define PL_REG_DROPPED_FRAME_COUNTER          0x014u

#define PL_REG_LATE_COMMIT_COUNTER            0x018u

#define PL_REG_OUTPUT_COUNT                   0x020u

#define PL_REG_MAX_PIXELS_PER_OUTPUT          0x024u

#define PL_REG_FRAME_BASE_ADDR                0x028u

#define PL_REG_IRQ_ENABLE                     0x02cu
#define PL_IRQ_FRAME_DONE                      (1u << 0)
#define PL_IRQ_UNDERRUN                        (1u << 1)
#define PL_IRQ_CONFIG_ERROR                    (1u << 2)
#define PL_IRQ_LATE_COMMIT                     (1u << 3)

#define PL_REG_IRQ_STATUS                     0x030u
#define PL_IRQ_STATUS_FRAME_DONE               (1u << 0)
#define PL_IRQ_STATUS_UNDERRUN                 (1u << 1)
#define PL_IRQ_STATUS_CONFIG_ERROR             (1u << 2)
#define PL_IRQ_STATUS_LATE_COMMIT              (1u << 3)

#define PL_REG_OUTPUT_PIXEL_COUNT             0x100u
#define PL_REG_OUTPUT_PIXEL_COUNT_STRIDE                        0x010u

#define PL_REG_OUTPUT_BUFFER_OFFSET           0x104u
#define PL_REG_OUTPUT_BUFFER_OFFSET_STRIDE                        0x010u

#define PL_REG_OUTPUT_FLAGS                   0x108u
#define PL_REG_OUTPUT_FLAGS_STRIDE                        0x010u
#define PL_OUTPUT_ENABLE                       (1u << 0)
#define PL_OUTPUT_REVERSED                     (1u << 1)
#define PL_OUTPUT_COLOR_ORDER_LSB_MASK                               0x00000300u
#define PL_OUTPUT_COLOR_ORDER_LSB_SHIFT                              8u

#define PL_REG_OUTPUT_BASE                         0x100u
#define PL_REG_OUTPUT_STRIDE                       0x010u

#endif /* PL_REGS_H */
