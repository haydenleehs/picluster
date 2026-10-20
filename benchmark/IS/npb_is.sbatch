#!/bin/bash
#SBATCH --job-name=npb-is
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks-per-node=4
#SBATCH --exclusive
#SBATCH --time=00:30:00
#SBATCH --output=/clusterfs/npb/is-%j.out

# NAS Parallel Benchmarks IS (integer sort): all-to-all key exchange, so it stresses the network.
#   sbatch npb_is.sbatch              # uses /clusterfs/npb/is.conf
#   sbatch npb_is.sbatch my.conf      # use a different input file
# Needs the build from build_npb_is.sh.

CONF=${1:-/clusterfs/npb/is.conf}
[ -r "$CONF" ] || { echo "input file not found: $CONF"; exit 1; }
source "$CONF"

BIN=/clusterfs/npb/NPB3.4.3/NPB3.4-MPI/bin/is.$CLASS.x
[ -x "$BIN" ] || { echo "IS binary for class $CLASS not found: $BIN (run build_npb_is.sh)"; exit 1; }

RES=/clusterfs/npb/results
mkdir -p "$RES"
CSV=$RES/is-$SLURM_JOB_ID.csv
ALLNODES=$(scontrol show hostnames "$SLURM_JOB_NODELIST")
NALLOC=$(echo "$ALLNODES" | wc -l)

echo "input: $CONF   class=$CLASS  configs='$CONFIGS'  repeats=$REPEATS"
echo "allocated nodes: $(echo $ALLNODES)"
echo "class,nodes,ranks,run,time_s,mops_total,verification" > "$CSV"

for cfg in $CONFIGS; do
  nn=${cfg%%:*}
  np=${cfg##*:}

  # IS needs a power-of-two rank count, and the nodes must be in the allocation
  if [ $((np & (np - 1))) -ne 0 ] || [ "$np" -lt 1 ]; then echo "skip $cfg: ranks must be a power of 2"; continue; fi
  if [ "$nn" -gt "$NALLOC" ]; then echo "skip $cfg: only $NALLOC nodes allocated"; continue; fi

  per=$(( (np + nn - 1) / nn ))
  HF=$RES/hostfile-$SLURM_JOB_ID-$nn-$np
  echo "$ALLNODES" | head -n "$nn" | awk -v s="$per" '{print $1 " slots=" s}' > "$HF"

  for r in $(seq "$REPEATS"); do
    out=$(mpirun --hostfile "$HF" -n "$np" --mca btl_tcp_if_include eth0 "$BIN" 2>&1)
    t=$(echo "$out"   | awk '/Time in seconds/{print $NF}')
    m=$(echo "$out"   | awk '/Mop\/s total/{print $NF}')
    v=$(echo "$out"   | awk '/Verification/{print $NF}')
    echo "$CLASS,$nn,$np,$r,${t:-NA},${m:-NA},${v:-FAILED_TO_RUN}" | tee -a "$CSV"
    [ -z "$m" ] && echo "$out" | tail -5
  done
  rm -f "$HF"
done

echo
echo "=== mean Mop/s total per config (higher is better) ==="
echo "nodes,ranks,mean_mops,mean_time_s"
awk -F, 'NR>1 && $6!="NA"{k=$2","$3; m[k]+=$6; t[k]+=$5; n[k]++} END{for(k in m) printf "%s,%.1f,%.2f\n", k, m[k]/n[k], t[k]/n[k]}' "$CSV" \
  | sort -t, -k1,1n -k2,2n
echo
awk -F, 'NR>1 && $7!="SUCCESSFUL"{print "CHECK: " $0; bad=1} END{if(!bad) print "all runs verified SUCCESSFUL"}' "$CSV"
echo "full results: $CSV"
