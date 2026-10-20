#!/bin/bash
#SBATCH --job-name=stream
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=1
#SBATCH --cpus-per-task=4
#SBATCH --exclusive
#SBATCH --time=00:15:00
#SBATCH --output=/clusterfs/stream/stream-%j.out

# STREAM memory bandwidth on each compute node (all nodes at once; memory is local to each node).
#   sbatch stream.sbatch                              # uses /clusterfs/stream/stream.conf
#   sbatch stream.sbatch my.conf                      # different input file
#   sbatch -N1 -w picluster-node01 stream.sbatch      # one node only
# Needs the binary built by build_stream.sh.

CONF=${1:-/clusterfs/stream/stream.conf}
[ -r "$CONF" ] || { echo "input file not found: $CONF"; exit 1; }
source "$CONF"

BIN=/clusterfs/stream/bin/stream_${ARRAY_SIZE}_${NTIMES}
[ -x "$BIN" ] || { echo "binary not found: $BIN (run build_stream.sh after editing the conf)"; exit 1; }

# --- memory guard: 3 arrays of 8-byte doubles must fit comfortably in RAM
MEM=$(awk '/MemTotal/{print $2 * 1024}' /proc/meminfo)
NEED=$((ARRAY_SIZE * 24))
echo "arrays need $((NEED / 1048576)) MiB of $((MEM / 1048576)) MiB RAM"
if [ "$NEED" -gt $((MEM * 60 / 100)) ] && [ -z "$FORCE" ]; then
  echo "ERROR: ARRAY_SIZE=$ARRAY_SIZE needs more than 60% of RAM. Lower it in $CONF and rebuild (or FORCE=1)."
  exit 1
fi

RES=/clusterfs/stream/results
mkdir -p "$RES"
RAW=$RES/stream-$SLURM_JOB_ID.raw
CSV=$RES/stream-$SLURM_JOB_ID.csv
WORKER=$RES/stream-worker-$SLURM_JOB_ID.sh
export BIN THREADS REPEATS

# --- per-node worker: one CSV line per run (rates in MB/s, best of NTIMES iterations)
cat > "$WORKER" <<'EOF'
#!/bin/bash
export OMP_PROC_BIND=true
for t in $THREADS; do
  for r in $(seq "$REPEATS"); do
    out=$(OMP_NUM_THREADS=$t "$BIN")
    cp=$(echo "$out" | awk '/^Copy:/{print $2}')
    sc=$(echo "$out" | awk '/^Scale:/{print $2}')
    ad=$(echo "$out" | awk '/^Add:/{print $2}')
    tr=$(echo "$out" | awk '/^Triad:/{print $2}')
    ok=$(echo "$out" | grep -c "Solution Validates")
    [ "$ok" -gt 0 ] && v=OK || v=CHECK
    temp=$(vcgencmd measure_temp | sed 's/[^0-9.]//g')
    thr=$(vcgencmd get_throttled | cut -d= -f2)
    echo "$(hostname),$t,$r,${cp:-NA},${sc:-NA},${ad:-NA},${tr:-NA},$v,$temp,$thr"
  done
done
EOF

echo "input: $CONF  (array=$ARRAY_SIZE ntimes=$NTIMES threads='$THREADS' repeats=$REPEATS)"
echo "nodes: $SLURM_JOB_NODELIST"
srun bash "$WORKER" > "$RAW"
rm -f "$WORKER"

{ echo "host,threads,run,copy_MBs,scale_MBs,add_MBs,triad_MBs,validated,temp_c,throttled"
  sort -t, -k1,1 -k2,2n -k3,3n "$RAW"; } > "$CSV"
rm -f "$RAW"

echo
echo "=== mean bandwidth per node, GB/s (higher is better; Triad is the headline number) ==="
echo "host,threads,copy,scale,add,triad,triad_best"
awk -F, 'NR>1 && $7!="NA"{k=$1","$2; c[k]+=$4; s[k]+=$5; a[k]+=$6; t[k]+=$7; n[k]++; if($7>b[k]) b[k]=$7}
  END{for(k in n) printf "%s,%.2f,%.2f,%.2f,%.2f,%.2f\n", k, c[k]/n[k]/1000, s[k]/n[k]/1000, a[k]/n[k]/1000, t[k]/n[k]/1000, b[k]/1000}' "$CSV" \
  | sort -t, -k1,1 -k2,2n

echo
awk -F, 'NR>1 && ($8!="OK" || $10!="0x0"){print "CHECK: " $0; bad=1} END{if(!bad) print "all runs validated, no throttling detected"}' "$CSV"
echo "full results: $CSV"
