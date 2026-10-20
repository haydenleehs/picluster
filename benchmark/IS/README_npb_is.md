# NPB IS network benchmark (Raspberry Pi 4B cluster)

Tests the cluster network with the **IS (Integer Sort)** kernel from the NAS Parallel Benchmarks (NPB 3.4.3, MPI version). IS ranks a large set of random integer keys. Every MPI rank exchanges keys with every other rank (all-to-all), so throughput depends heavily on the network.

Cluster: login node `picluster-login`, compute nodes `picluster-node01` to `picluster-node04`, shared storage `/clusterfs` (NFS), jobs scheduled with SLURM.

## Files

| File | What it does |
|---|---|
| `build_npb_is.sh` | One-time: installs the compiler and MPI, downloads NPB, builds IS |
| `is.conf` | Input file: problem class, node/rank layouts, repeats |
| `npb_is.sbatch` | SLURM job script: runs IS for each layout and summarises the results |

## Requirements

- MPI (`openmpi-bin`) on all nodes (Stage 4 of the build guide)
- SLURM working (`sinfo` shows 4 idle nodes) and NFS mounted at `/clusterfs` on every node
- Internet on the login node for the one-time download
- Compute nodes use `eth0` for the cluster LAN

## Setup (once)

On `picluster-login`:

```bash
bash build_npb_is.sh              # builds classes A, B and C
# or just one class:  bash build_npb_is.sh B

cp is.conf npb_is.sbatch /clusterfs/npb/
```

Binaries end up in `/clusterfs/npb/NPB3.4.3/NPB3.4-MPI/bin/is.<CLASS>.x`.

## Run

Always submit from `/clusterfs/npb` so the compute nodes can see the files:

```bash
cd /clusterfs/npb
sbatch npb_is.sbatch              # uses is.conf
sbatch npb_is.sbatch other.conf   # use a different input file
squeue                            # wait until the job disappears
cat is-<jobid>.out
```

The job reserves all 4 nodes exclusively, so nothing else runs at the same time and skews the results.

## Input file (`is.conf`)

| Variable | Meaning |
|---|---|
| `CLASS` | Problem size: `A` (quick test), `B` (normal), `C` (large, use only with 4 nodes). Fixed when IS is built, so the class must already be built. |
| `CONFIGS` | Space-separated `nodes:ranks` pairs, run in order. Ranks must be 1, 2, 4, 8 or 16 (IS needs a power of two). |
| `REPEATS` | Runs per layout, to see run-to-run variation. |

Default layouts and what each shows:

| Layout | Meaning |
|---|---|
| `1:1` | Baseline, no communication |
| `1:4` | 4 ranks on one node, traffic stays in shared memory (no network) |
| `2:2` | 1 rank per node on 2 nodes, network is the only link |
| `4:4` | 1 rank per node on 4 nodes, all-to-all over 1 GbE |
| `4:16` | 4 ranks per node on 4 nodes, network plus on-node traffic |

## Output

- `is-<jobid>.out` has the per-run lines, the mean per layout, and a verification check.
- `/clusterfs/npb/results/is-<jobid>.csv` has every run: `class,nodes,ranks,run,time_s,mops_total,verification`.

Key numbers:

- **`mops_total`**: millions of keys ranked per second. Higher is better.
- **`time_s`**: wall time for the sort. Lower is better.
- **`verification`**: must be `SUCCESSFUL`. Don't use results from a run that isn't.

## Reading the results

- Compare `1:4` against `4:4`. Both use 4 ranks, so the difference is the cost of going over the network.
- Compare `2:2` against `4:4`. If doubling the nodes barely raises Mop/s (or lowers it), the network is the bottleneck.
- Expect poor scaling. Each node has a single 1 GbE link (about 110 MB/s in practice), and IS is communication-heavy. That gap is the result.
- Run each layout a few times. If runs differ a lot, check temperature and throttling with `vcgencmd measure_temp` and `vcgencmd get_throttled` (should be `0x0`).

## Troubleshooting

| Problem | Fix |
|---|---|
| `IS binary for class X not found` | Run `build_npb_is.sh` for that class |
| `skip ...: ranks must be a power of 2` | Fix `CONFIGS` in `is.conf` |
| `skip ...: only N nodes allocated` | The job asks for 4 nodes; check `sinfo` for down or drained nodes |
| Job stays `PD` in `squeue` | Check the REASON column, or `sinfo -R` |
| Download fails | Check the login node has internet; download `NPB3.4.3.tar.gz` manually into `/clusterfs/npb/` and re-run the build |
| MPI can't connect between nodes | Confirm the LAN interface is `eth0` with `ssh picluster-node01 "ip -br a"`; change `btl_tcp_if_include` in `npb_is.sbatch` if it has a different name |
| Class C runs out of memory | Use `4:4` or `4:16` only, or drop to class B |
| Verification is not `SUCCESSFUL` | Discard that run and repeat it |

## Notes

- Results from this cluster are for comparing layouts with each other, not with published supercomputer numbers.
- IS is a network and memory test, not a floating-point test, so its numbers are in Mop/s, not GFLOPS.
