#!/usr/bin/env python3
import argparse
import math
import socket
import struct
import time
import uuid

from generated import pl_config


PIXELS_PER_OUTPUT = pl_config.DEFAULT_STRAND_PIXEL_COUNT
OUTPUT_COUNT = pl_config.DEFAULT_ACTIVE_OUTPUT_COUNT
SLOTS_PER_UNIVERSE = 510
TOTAL_PIXELS = PIXELS_PER_OUTPUT * OUTPUT_COUNT
TOTAL_SLOTS = TOTAL_PIXELS * 3
DEFAULT_CID = uuid.UUID("d06d0ead-beef-4000-8000-000000000001")
DEFAULT_SYNC_ADDRESS = 63999


def rgb_for_pixel(pattern, pixel, frame):
    output = pixel // PIXELS_PER_OUTPUT
    index = pixel % PIXELS_PER_OUTPUT
    if pattern == "red":
        return 255, 0, 0
    if pattern == "green":
        return 0, 255, 0
    if pattern == "blue":
        return 0, 0, 255
    if pattern == "white":
        return 64, 64, 64
    if pattern == "bars":
        colors = ((255, 0, 0), (0, 255, 0), (0, 0, 255), (64, 64, 64))
        return colors[output % len(colors)]
    if pattern == "chase":
        return (255, 128, 16) if ((index + frame * 4 + output * 32) % 128) < 16 else (0, 0, 0)
    phase = (index + frame + output * 64) & 0xFF
    return phase, 255 - phase, (frame + output * 32) & 0xFF


def build_slots(pattern, first_slot, slot_count, frame):
    slots = bytearray()
    for slot in range(first_slot, first_slot + slot_count, 3):
        pixel = slot // 3
        if pixel < TOTAL_PIXELS:
            slots.extend(rgb_for_pixel(pattern, pixel, frame))
        else:
            slots.extend((0, 0, 0))
    return bytes(slots[:slot_count])


def flags_and_length(length):
    return 0x7000 | length


def build_packet(universe, sequence, slots, cid, priority, sync_address, options):
    prop_count = len(slots) + 1
    total_len = 126 + len(slots)
    packet = bytearray(total_len)
    packet[0:2] = struct.pack(">H", 0x0010)
    packet[2:4] = struct.pack(">H", 0x0000)
    packet[4:16] = b"ASC-E1.17\x00\x00\x00"
    packet[16:18] = struct.pack(">H", flags_and_length(total_len - 16))
    packet[18:22] = struct.pack(">I", 0x00000004)
    packet[22:38] = cid.bytes
    packet[38:40] = struct.pack(">H", flags_and_length(total_len - 38))
    packet[40:44] = struct.pack(">I", 0x00000002)
    source = b"dawn e131 sender"
    packet[44:44 + len(source)] = source
    packet[108] = priority
    packet[109:111] = struct.pack(">H", sync_address)
    packet[111] = sequence & 0xFF
    packet[112] = options
    packet[113:115] = struct.pack(">H", universe)
    packet[115:117] = struct.pack(">H", flags_and_length(total_len - 115))
    packet[117] = 0x02
    packet[118] = 0xA1
    packet[119:121] = struct.pack(">H", 0)
    packet[121:123] = struct.pack(">H", 1)
    packet[123:125] = struct.pack(">H", prop_count)
    packet[125] = 0
    packet[126:] = slots
    return bytes(packet)


def build_sync_packet(sequence, cid, sync_address):
    total_len = 49
    packet = bytearray(total_len)
    packet[0:2] = struct.pack(">H", 0x0010)
    packet[2:4] = struct.pack(">H", 0x0000)
    packet[4:16] = b"ASC-E1.17\x00\x00\x00"
    packet[16:18] = struct.pack(">H", flags_and_length(total_len - 16))
    packet[18:22] = struct.pack(">I", 0x00000008)
    packet[22:38] = cid.bytes
    packet[38:40] = struct.pack(">H", flags_and_length(total_len - 38))
    packet[40:44] = struct.pack(">I", 0x00000001)
    packet[44] = sequence & 0xFF
    packet[45:47] = struct.pack(">H", sync_address)
    packet[47:49] = struct.pack(">H", 0)
    return bytes(packet)


def parse_args():
    default_universe_count = math.ceil(TOTAL_SLOTS / SLOTS_PER_UNIVERSE)
    parser = argparse.ArgumentParser(description="Send deterministic E1.31/sACN data packets.")
    parser.add_argument("--dest-ip", default="192.168.7.2")
    parser.add_argument("--port", type=int, default=5568)
    parser.add_argument("--first-universe", type=int, default=1)
    parser.add_argument("--universe-count", type=int, default=default_universe_count)
    parser.add_argument("--pattern", choices=("gradient", "bars", "chase", "red", "green", "blue", "white"), default="gradient")
    parser.add_argument("--packet-count", type=int, default=0, help="Frame count to send; 0 means run until Ctrl+C.")
    parser.add_argument("--rate", type=float, default=30.0, help="Frame rate in complete universe sweeps per second.")
    parser.add_argument("--priority", type=int, default=100)
    parser.add_argument("--source-cid", default=str(DEFAULT_CID))
    parser.add_argument("--preview", action="store_true")
    parser.add_argument("--stream-terminate", action="store_true")
    parser.add_argument("--sync-address", type=int, default=0, help="0 sends unsynced data packets.")
    parser.add_argument("--send-sync", action="store_true", help=f"Emit an E1.31 sync packet after each sweep. Defaults to sync universe {DEFAULT_SYNC_ADDRESS} when --sync-address is omitted.")
    return parser.parse_args()


def main():
    args = parse_args()
    delay = 0.0 if args.rate <= 0 else 1.0 / args.rate
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    cid = uuid.UUID(args.source_cid)
    sync_address = args.sync_address
    if args.send_sync and sync_address == 0:
        sync_address = DEFAULT_SYNC_ADDRESS
    data_options = 0
    if args.preview:
        data_options |= 0x80
    if args.stream_terminate:
        data_options |= 0x40
    frame = 0
    sequence = 0
    sync_sequence = 0
    try:
        while args.packet_count == 0 or frame < args.packet_count:
            for offset in range(args.universe_count):
                first_slot = offset * SLOTS_PER_UNIVERSE
                slot_count = min(SLOTS_PER_UNIVERSE, max(0, TOTAL_SLOTS - first_slot))
                if slot_count <= 0:
                    break
                slots = build_slots(args.pattern, first_slot, slot_count, frame)
                packet = build_packet(args.first_universe + offset, sequence, slots, cid, args.priority, sync_address, data_options)
                sock.sendto(packet, (args.dest_ip, args.port))
                sequence = (sequence + 1) & 0xFF
            if args.send_sync:
                packet = build_sync_packet(sync_sequence, cid, sync_address)
                sock.sendto(packet, (args.dest_ip, args.port))
                sync_sequence = (sync_sequence + 1) & 0xFF
            frame += 1
            if delay > 0:
                time.sleep(delay)
    except KeyboardInterrupt:
        pass
    print(f"sent_frames={frame} dest={args.dest_ip}:{args.port} first_universe={args.first_universe} universe_count={args.universe_count} pattern={args.pattern} priority={args.priority} cid={cid} sync_address={sync_address} send_sync={args.send_sync}")


if __name__ == "__main__":
    main()
