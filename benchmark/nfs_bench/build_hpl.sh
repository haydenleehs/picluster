#!/bin/bash
# One-time HPL 2.3 build. Run on picluster-login:  bash build_hpl.sh
# Result: /clusterfs/hpl/hpl-2.3/bin/rpi/xhpl  (shared with all nodes over NFS)
set -e

NODES="picluster-node01 picluster-node02 picluster-node03 picluster-node04"
BASE=/clusterfs/hpl

echo "== install build tools (login) and OpenBLAS runtime (compute nodes)"
sudo apt update
sudo apt install -y build-essential gfortran libopenmpi-dev libopenblas-dev
for h in $NODES; do ssh $h "sudo apt install -y libopenblas0"; done

echo "== download HPL"
mkdir -p $BASE && cd $BASE
[ -f hpl-2.3.tar.gz ] || wget https://netlib.org/benchmark/hpl/hpl-2.3.tar.gz
rm -rf hpl-2.3 && tar xf hpl-2.3.tar.gz
cd hpl-2.3

echo "== write Make.rpi"
( cd setup && sh make_generic && cp Make.UNKNOWN ../Make.rpi )
sed -i \
  -e "s|^ARCH .*|ARCH       = rpi|" \
  -e "s|^TOPdir .*|TOPdir     = $PWD|" \
  -e "s|^CC .*|CC         = mpicc|" \
  -e "s|^LINKER .*|LINKER     = mpicc|" \
  -e "s|^LAlib .*|LAlib      = -lopenblas|" \
  -e "s|^CCFLAGS .*|CCFLAGS    = -O3 -mcpu=native|" \
  Make.rpi

echo "== build"
make arch=rpi

echo "== check"
ls -l bin/rpi/xhpl
ldd bin/rpi/xhpl | grep -i blas || echo "WARNING: no BLAS library linked"
echo "Done. Use: XHPL_BIN=$PWD/bin/rpi/xhpl"
