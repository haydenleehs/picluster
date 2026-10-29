#!/usr/bin/env python3
"""Four vertical bars on a MAX7219 8x8 matrix, one bar per CPU core.

Each core owns two columns. Bar height tracks that core's utilisation
over the last sampling interval, read from /proc/stat. Readings are
smoothed with an exponential moving average so sub-second blips (like
MPI process startup) barely register, while sustained load shows at
full height. Runs forever; clears the display on exit.

When the busiest core is below THRESHOLD the node shows its own letter
instead (node01=C, node02=S, node03=C, node04=N; physically arranged so
the four boards read N S C C), so the four matrices spell NSCC at rest
and turn into load bars while a job runs.

Idle-state extras (new):
  - Breathing brightness: the letters slowly dim and brighten instead
    of sitting at a flat intensity.
  - Wipe transitions: switching between letter <-> bars draws/erases
    the letter column by column instead of snapping instantly.
  - Cluster ripple: a brightness wave sweeps left-to-right across the
    four boards (N -> S -> C -> C) in a loop, using each Pi's wall
    clock to agree on where the wave currently is. Needs the nodes'
    clocks to be roughly in sync (true once they're online via NTP),
    a few hundred ms of drift is invisible at RIPPLE_PERIOD=4s.
"""
import math
import signal
import socket
import sys
import time

import spidev

INTERVAL   = 0.05  # seconds between samples (fast enough for smooth animation)
BRIGHT_MAX = 3      # ceiling intensity (0..15); keep modest, it is plenty
BRIGHT_MIN = 1      # floor intensity for the breathing idle effect
ROTATE     = 2       # 0/1/2/3 = quarter turns, adjust to your module's mounting
SMOOTH     = 0.5     # 0 = raw readings, closer to 1 = smoother/slower
THRESHOLD  = 0.15    # busiest core above this -> show bars, else show the letter

WIPE_SECONDS   = 0.35  # time to wipe a letter in/out on state change
BREATHE_PERIOD = 3.0   # seconds per idle breathing cycle
RIPPLE_PERIOD  = 4.0   # seconds for one ripple sweep across all 4 boards
RIPPLE_WIDTH   = 1.0   # how many board-positions wide the bright band is

# 8 row-bytes per letter, top row first, leftmost column = highest bit
LETTERS = {
    "N": [0xC6, 0xE6, 0xF6, 0xDE, 0xCE, 0xC6, 0xC6, 0x00],
    "S": [0x78, 0xCC, 0xE0, 0x70, 0x1C, 0xCC, 0x78, 0x00],
    "C": [0x3C, 0x66, 0xC0, 0xC0, 0xC0, 0x66, 0x3C, 0x00],
}
LETTER_FOR = {
    "picluster-node01": "C",
    "picluster-node02": "S",
    "picluster-node03": "C",
    "picluster-node04": "N",
}
# Left-to-right physical position in the "N S C C" row, used for the ripple.
# Edit this if you ever re-wire the boards into a different order.
POSITION = {
    "picluster-node04": 0,   # N
    "picluster-node02": 1,   # S
    "picluster-node01": 2,   # C
    "picluster-node03": 3,   # C
}

HOST = socket.gethostname()
IDLE = LETTERS.get(LETTER_FOR.get(HOST, ""), [0] * 8)
POS  = POSITION.get(HOST, 0)

spi = spidev.SpiDev()
spi.open(0, 0)                # bus 0, CE0
spi.max_speed_hz = 1_000_000

def cmd(reg, val):
    spi.xfer2([reg, val])

def set_brightness(level):
    cmd(0x0A, max(0, min(15, level)))

def init_display():
    cmd(0x0F, 0x00)           # display-test off
    cmd(0x09, 0x00)           # no BCD decode, raw bits
    cmd(0x0B, 0x07)           # scan all 8 digits
    set_brightness(BRIGHT_MAX)
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

def wipe_frame(target_fb, progress):
    """target_fb masked to the leftmost `progress` fraction of its columns."""
    cols_on = round(max(0.0, min(1.0, progress)) * 8)
    mask = (0xFF << (8 - cols_on)) & 0xFF
    return [row & mask for row in target_fb]

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

def idle_brightness(now):
    """Breathing brightness, with a brief bright flash when the cluster
    ripple wave passes this board's position."""
    breathe = (math.sin(now * 2 * math.pi / BREATHE_PERIOD) + 1) / 2   # 0..1
    bright = round(BRIGHT_MIN + breathe * (BRIGHT_MAX - BRIGHT_MIN))

    phase = (now % RIPPLE_PERIOD) / RIPPLE_PERIOD * 4   # 0..4, sweeps across 4 positions
    dist = min(abs(phase - POS), abs(phase - POS - 4), abs(phase - POS + 4))
    if dist < RIPPLE_WIDTH:
        bright = BRIGHT_MAX
    return bright

def animate_wipe(target_fb, steps):
    """steps: iterable of progress values 0..1 (or reversed for wipe-out)."""
    for p in steps:
        set_brightness(BRIGHT_MAX)
        show(wipe_frame(target_fb, p))
        time.sleep(WIPE_SECONDS / 6)

def shutdown(*_):
    clear()
    cmd(0x0C, 0x00)
    spi.close()
    sys.exit(0)

signal.signal(signal.SIGTERM, shutdown)
signal.signal(signal.SIGINT, shutdown)

init_display()
animate_wipe(IDLE, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])   # wipe the letter in at boot

prev = read_cores()
ema  = [0.0] * len(prev)
was_idle = True

while True:
    time.sleep(INTERVAL)
    cur = read_cores()
    loads = []
    for cpu in sorted(prev):
        db = cur[cpu][0] - prev[cpu][0]
        dt = cur[cpu][1] - prev[cpu][1]
        loads.append(db / dt if dt > 0 else 0.0)
    ema = [SMOOTH * e + (1 - SMOOTH) * l for e, l in zip(ema, loads)]
    busy = max(ema) > THRESHOLD

    if busy:
        if was_idle:
            animate_wipe(IDLE, [1.0, 0.6, 0.2, 0.0])   # wipe the letter out
            was_idle = False
        set_brightness(BRIGHT_MAX)
        show(bar_frame(ema))
    else:
        if not was_idle:
            animate_wipe(IDLE, [0.0, 0.3, 0.6, 1.0])   # wipe the letter back in
            was_idle = True
        set_brightness(idle_brightness(time.time()))
        show(IDLE)

    prev = cur
