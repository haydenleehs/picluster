#!/bin/bash
#SBATCH --job-name=rpi4_hpl
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:30:00
#SBATCH --output=hpl_%j.out

cd "$SLURM_SUBMIT_DIR" || exit 1
export OMP_NUM_THREADS=1 OPENBLAS_NUM_THREADS=1

XHPL_BIN=$(command -v xhpl || find /usr -name xhpl -type f 2>/dev/null | head -n 1)
[ -x "$XHPL_BIN" ] || { echo "xhpl not found on $(hostname)"; exit 1; }
[ -r HPL.dat ]     || { echo "HPL.dat not found in $PWD"; exit 1; }

echo "xhpl: $XHPL_BIN   ranks: $SLURM_NTASKS"
mpirun -np "$SLURM_NTASKS" "$XHPL_BIN"

echo "$(hostname) $(vcgencmd measure_temp) $(vcgencmd get_throttled)"
