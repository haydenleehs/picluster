#!/bin/bash
# Build STREAM with the sizes from stream.conf. Run on picluster-login:
#   bash build_stream.sh [conf]        # default conf: /clusterfs/stream/stream.conf
# Re-run it whenever you change ARRAY_SIZE or NTIMES in the conf.
# Result: /clusterfs/stream/bin/stream_<ARRAY_SIZE>_<NTIMES>
set -e

BASE=/clusterfs/stream
CONF=${1:-$BASE/stream.conf}
[ -r "$CONF" ] || { echo "input file not found: $CONF"; exit 1; }
source "$CONF"

echo "== install compiler + git (login node) and the OpenMP runtime (compute nodes)"
sudo apt update
sudo apt install -y build-essential git
for h in picluster-node0{1..4}; do ssh $h "sudo apt install -y libgomp1"; done

echo "== find or download stream.c"
mkdir -p "$BASE/bin" && cd "$BASE"
SRC=$(find "$BASE" -name stream.c | head -n 1)
if [ -z "$SRC" ]; then
  git clone --depth 1 https://github.com/jeffhammond/STREAM.git
  SRC=$BASE/STREAM/stream.c
fi
echo "source: $SRC"

echo "== compile (array size $ARRAY_SIZE, NTIMES $NTIMES)"
BIN=$BASE/bin/stream_${ARRAY_SIZE}_${NTIMES}
gcc -O3 -mcpu=native -fopenmp \
    -DSTREAM_ARRAY_SIZE=$ARRAY_SIZE -DNTIMES=$NTIMES \
    "$SRC" -o "$BIN"

echo "== check"
ls -l "$BIN"
echo "Done. Next: sbatch /clusterfs/stream/stream.sbatch"
