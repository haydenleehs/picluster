#!/bin/bash
#SBATCH --job-name=nfs_fio
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --time=00:05:00
#SBATCH --output=nfs_bench_%j.out

cd "$SLURM_SUBMIT_DIR" || exit 1

echo "===================================================="
echo " Running NFS Benchmark from Client: $(hostname)"
echo " Target NFS Directory             : $(pwd)"
echo "===================================================="

# Run fio using the nfs_bench.fio input file
fio nfs_bench.fio -- directory="$(pwd)"
