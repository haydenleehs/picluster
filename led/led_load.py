#!/usr/bin/env python3
"""Four vertical bars on a MAX7219 8x8 matrix, one bar per CPU core.

Each core owns two columns. Bar height tracks that core's utilisation
over the last sampling interval, read from /proc/stat. Readings are
smoothed with an exponential moving average so sub-second blips (like
MPI process startup) barely register, while sustained load shows at
full height. Runs forever; clears the display on exit.

When the busiest core is below THRESHOLD the node shows its own letter
instead (node01=N, node02=S, node03=C, node04=C), so the four matrices
spell NSCC at rest and turn into load bars while a job runs.
"""
import signal
import socket
import sys
import time

import spidev

INTERVAL  = 0.2   # seconds between samples
BRIGHT    = 4     # 0 (dim) .. 15 (blinding); keep low, it is plenty
ROTATE    = 0     # 0/1/2/3 = quarter turns, adjust to your module's mounting
SMOOTH    = 0.5   # 0 = raw readings, closer to 1 = smoother/slower
THRESHOLD = 0.15  # busiest core above this -> show bars, else show the letter

# 8 row-bytes per letter, top row first, leftmost column = highest bit
LETTERS = {
    "N": [0xC6, 0xCE, 0xDE, 0xF6, 0xE6, 0xC6, 0xC6, 0x00],
    "S": [0x78, 0xCC, 0xE0, 0x70, 0x1C, 0xCC, 0x78, 0x00],
    "C": [0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C, 0x00],
}
LETTER_FOR = {
    "picluster-node01": "N",
    "picluster-node02": "S",
    "picluster-node03": "C",
    "picluster-node04": "C",
}
IDLE = LETTERS.get(LETTER_FOR.get(socket.gethostname(), ""), [0] * 8)

spi = spidev.SpiDev()
spi.open(0, 0)                # bus 0, CE0
spi.max_speed_hz = 1_000_000

def cmd(reg, val):
    spi.xfer2([reg, val])

def init_display():
    cmd(0x0F, 0x00)           # display-test off
    cmd(0x09, 0x00)           # no BCD decode, raw bits
    cmd(0x0B, 0x07)           # scan all 8 digits
    cmd(0x0A, BRIGHT)         # intensity
    cmd(0x0C, 0x01)           # leave shutdown mode
    clear()

def clear():
    for d in range(8):
        cmd(d + 1, 0x00)

def rotate(fb):
    for _ in range(ROTATE):
        fb = [sum(((fb[7 - c] >> (7 - r)) & 1) << (7 - c) for c in range(8))
              for r in range(8)]
    return fb

def show(fb):                 # fb = 8 row-bytes, fb[0] is the top row
    fb = rotate(fb)
    for r in range(8):
        cmd(r + 1, fb[r])

def read_cores():
    """Return {'cpu0': (busy, total), ...} in jiffies."""
    out = {}
    with open("/proc/stat") as f:
        for line in f:
            if line.startswith("cpu") and line[3].isdigit():
                p = line.split()
                idle  = int(p[4]) + int(p[5])          # idle + iowait
                total = sum(int(x) for x in p[1:8])
                out[p[0]] = (total - idle, total)
    return out

def bar_frame(loads):
    """loads = per-core fractions 0..1 -> 8 row-bytes, bars rise from the bottom."""
    heights = [round(l * 8) for l in loads]
    fb = []
    for row in range(8):                               # row 0 = top
        byte = 0
        for core, h in enumerate(heights[:4]):
            if h >= 8 - row:                           # bar tall enough to reach this row
                byte |= 0b11 << (6 - 2 * core)         # two columns per core
        fb.append(byte)
    return fb

def shutdown(*_):
    clear()
    cmd(0x0C, 0x00)
    spi.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

init_display()
prev = read_cores()
ema  = [0.0] * len(prev)
while True:
    time.sleep(INTERVAL)
    cur = read_cores()
    loads = []
    for cpu in sorted(prev):
        db = cur[cpu][0] - prev[cpu][0]
        dt = cur[cpu][1] - prev[cpu][1]
        loads.append(db / dt if dt > 0 else 0.0)
    ema = [SMOOTH * e + (1 - SMOOTH) * l for e, l in zip(ema, loads)]
    if max(ema) > THRESHOLD:
        show(bar_frame(ema))
    else:
        show(IDLE)
    prev = cur
