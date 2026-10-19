#!/bin/bash
#SBATCH --job-name=lammps_lj
#SBATCH --nodes=1
#SBATCH --ntasks-per-node=4
#SBATCH --cpus-per-task=1
#SBATCH --time=00:10:00
#SBATCH --output=lammps_%j.out

cd "$SLURM_SUBMIT_DIR" || exit 1

# Lock OpenMP to 1 thread per MPI rank to avoid oversubscribing the 4 cores
export OMP_NUM_THREADS=${SLURM_CPUS_PER_TASK:-1}

# Find the LAMMPS binary (named 'lmp' or 'lammps' depending on distro)
LMP_BIN=$(command -v lmp || command -v lammps)

echo "===================================================="
echo " Node      : $(hostname)"
echo " Job ID    : $SLURM_JOB_ID"
echo " MPI Ranks : $SLURM_NTASKS"
echo " Binary    : $LMP_BIN"
echo "===================================================="

# Run the simulation using the in.lj input file
mpirun -np "$SLURM_NTASKS" "$LMP_BIN" -in in.lj -log "log.lammps.${SLURM_JOB_ID}"
