#!/bin/bash
# One-time build of the NAS Parallel Benchmarks IS (integer sort) kernel, MPI version.
# Run on picluster-login:  bash build_npb_is.sh [classes]     e.g. bash build_npb_is.sh "A B C"
# Result: /clusterfs/npb/NPB3.4.3/NPB3.4-MPI/bin/is.<CLASS>.x  (shared with all nodes over NFS)
set -e

CLASSES=${1:-"A B C"}
BASE=/clusterfs/npb
VER=NPB3.4.3

echo "== install compiler + MPI (login node); compute nodes only need the MPI runtime"
sudo apt update
sudo apt install -y build-essential libopenmpi-dev openmpi-bin
for h in picluster-node0{1..4}; do ssh $h "sudo apt install -y openmpi-bin"; done

echo "== download $VER"
mkdir -p $BASE && cd $BASE
[ -f $VER.tar.gz ] || wget https://www.nas.nasa.gov/assets/npb/$VER.tar.gz
[ -d $VER ] || tar xf $VER.tar.gz
cd $VER/NPB3.4-MPI

echo "== write config/make.def (IS is plain C, so no Fortran settings are needed)"
cat > config/make.def <<'EOF'
MPICC      = mpicc
CLINK      = mpicc
CMPI_LIB   =
CMPI_INC   =
CFLAGS     = -O3
CLINKFLAGS = $(CFLAGS)
CC         = cc -g
BINDIR     = ../bin
RAND       = randi8
C_LIB      = -lm
WTIME      = wtime.c
EOF

echo "== build IS for classes: $CLASSES"
for c in $CLASSES; do
  make is CLASS=$c
done

echo "== check"
ls -l bin/is.*
echo "Done. Next: cp is.conf npb_is.sbatch /clusterfs/npb/ && sbatch /clusterfs/npb/npb_is.sbatch"
