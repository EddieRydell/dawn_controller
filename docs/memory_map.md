# PS/PL Memory Map

_Generated from `memory_map.yaml`. Do not edit by hand._

PS/PL register and frame-buffer contract for the Donder controller.

## AXI-Lite Registers

| Offset | Name | Access | Description |
| --- | --- | --- | --- |
| `0x000` | `CONTROL` | RW | Control register. Commit is a pulse; PL latches it and swaps at a frame boundary. |
| `0x004` | `STATUS` | RO | PL status flags. |
| `0x008` | `ACTIVE_BANK` | RO | Frame bank currently consumed by PL. |
| `0x00c` | `WRITE_BANK` | RW | Frame bank the PS is submitting. |
| `0x010` | `FRAME_COUNTER` | RO | Frame commits accepted by PL. |
| `0x014` | `DROPPED_FRAME_COUNTER` | RO | Reserved for queued-frame overwrite/drop accounting. |
| `0x018` | `LATE_COMMIT_COUNTER` | RO | Commits rejected because PL was not ready for a new frame. |
| `0x020` | `OUTPUT_COUNT` | RW | Active WS2811 output lane count. |
| `0x024` | `MAX_PIXELS_PER_OUTPUT` | RO | Synthesis-time maximum pixels per output. |
| `0x028` | `FRAME_BASE_ADDR` | RW | Physical base address of frame bank 0 in PS DDR. |
| `0x02c` | `IRQ_ENABLE` | RW | Interrupt enable mask. |
| `0x030` | `IRQ_STATUS` | RW | Sticky interrupt status. Write one to a bit to clear it. |
| `0x100 + n*0x010` | `OUTPUT_PIXEL_COUNT` | RW | Runtime pixel count for output n. |
| `0x104 + n*0x010` | `OUTPUT_BUFFER_OFFSET` | RW | Byte offset for output n within each frame bank. |
| `0x108 + n*0x010` | `OUTPUT_FLAGS` | RW | Runtime flags for output n. |

## Fields

| Register | Field | Bits | Description |
| --- | --- | --- | --- |
| `CONTROL` | `ENABLE` | `0` | Enable PL output. |
| `CONTROL` | `COMMIT_FRAME` | `1` | Pulse to submit the currently selected write bank. |
| `STATUS` | `BUSY` | `0` | PL is actively transmitting a WS2811 frame. |
| `STATUS` | `FRAME_PENDING` | `1` | A committed frame is waiting for the next boundary. |
| `STATUS` | `UNDERRUN` | `2` | WS transmitter ran out of pixel data during an active frame. |
| `STATUS` | `CONFIG_ERROR` | `3` | Runtime config exceeds synthesis limits or is internally inconsistent. |
| `STATUS` | `READY_FOR_FRAME` | `4` | PL is enabled and ready to accept a new frame commit. |
| `IRQ_ENABLE` | `IRQ_FRAME_DONE` | `0` | Enable interrupt when a committed frame finishes. |
| `IRQ_ENABLE` | `IRQ_UNDERRUN` | `1` | Enable interrupt on WS transmitter underrun. |
| `IRQ_ENABLE` | `IRQ_CONFIG_ERROR` | `2` | Enable interrupt on runtime configuration error. |
| `IRQ_ENABLE` | `IRQ_LATE_COMMIT` | `3` | Enable interrupt when a frame commit is rejected. |
| `IRQ_STATUS` | `IRQ_STATUS_FRAME_DONE` | `0` | A committed frame finished. |
| `IRQ_STATUS` | `IRQ_STATUS_UNDERRUN` | `1` | WS transmitter underrun occurred. |
| `IRQ_STATUS` | `IRQ_STATUS_CONFIG_ERROR` | `2` | Runtime configuration error occurred. |
| `IRQ_STATUS` | `IRQ_STATUS_LATE_COMMIT` | `3` | A frame commit was rejected. |
| `OUTPUT_FLAGS` | `OUTPUT_ENABLE` | `0` | Enable this output. |
| `OUTPUT_FLAGS` | `OUTPUT_REVERSED` | `1` | Transmit pixels in reverse order. |
| `OUTPUT_FLAGS` | `OUTPUT_COLOR_ORDER_LSB` | `9:8` | Color order enum field, bits 9:8. |

## Frame Buffer

Frame data is stored as 32-bit normalized RGB pixels.

- Pixel format: `0x00RRGGBB`
- Pixel bytes: `4`
- Bank count symbol: `DONDER_FRAME_BANKS`
- Output count symbol: `DONDER_MAX_OUTPUTS`
- Pixels per output symbol: `DONDER_MAX_PIXELS_PER_OUTPUT`

Frame bank addressing:

```text
bank_base + output_buffer_offset[n] + pixel_index * pixel_bytes
```

## Determinism Contract

- PL never stalls a WS2811 waveform once started.
- PL only accepts a frame commit when `STATUS.READY_FOR_FRAME` is set.
- PL rejects commits while busy and increments `LATE_COMMIT_COUNTER`.
- PL never changes `ACTIVE_BANK` for a rejected commit.
- PS only submits a frame after the target bank has been fully written and cache-flushed.
