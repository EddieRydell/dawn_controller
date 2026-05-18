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
| `0x010` | `FRAME_COUNTER` | RO | Frames accepted by PL. |
| `0x014` | `DROPPED_FRAME_COUNTER` | RO | Frames skipped or overwritten before display. |
| `0x018` | `LATE_COMMIT_COUNTER` | RO | Commits received too late for the configured cadence. |
| `0x020` | `OUTPUT_COUNT` | RW | Active WS2811 output lane count. |
| `0x024` | `MAX_PIXELS_PER_OUTPUT` | RO | Synthesis-time maximum pixels per output. |
| `0x028` | `FRAME_BASE_ADDR` | RW | Physical base address of frame bank 0 in PS DDR. |
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
| `STATUS` | `UNDERRUN` | `2` | PL had no complete new frame and repeated the previous frame. |
| `STATUS` | `CONFIG_ERROR` | `3` | Runtime config exceeds synthesis limits or is internally inconsistent. |
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
- PL only swaps banks at a frame boundary.
- PL repeats the previous frame if no complete new frame is ready.
- PS only writes the inactive bank.
