# Evolve a Wing: Raspberry Pi Cluster Demo

The Pi cluster breeds thousands of wing designs. Each node is an "island" that evolves its own
population and swaps its best wings with its neighbour. A web page shows the best wing reshaping
live, and visitors can try to beat the cluster by setting their own wing.

| File | Where it runs | What it does |
|---|---|---|
| `evolve.html` | Your browser | Live page: wind tunnel with the current best wing, fitness curve, stats, "Race the Cluster" |
| `aero_evolve.py` | Pi cluster (MPI via SLURM) | Island-model genetic algorithm; rank 0 writes `best.json` after every generation |
| `evolve.sh` | Login node | SLURM job script (rank count set at submit time) |

All files live in `/clusterfs/aero_evolve/` (shared by every node over NFS).
The page reads `best.json` from the same folder once a second.

---

## 1. Setup (once)

**Needs:** SLURM working (`sinfo` shows 4 idle nodes), NFS mounted at `/clusterfs`, and `openmpi-bin`,
`python3-mpi4py`, `python3-numpy` on every node (all from Stage 4 of the build guide).

**a) Make the folder and copy the files.** From your laptop, plugged into the cluster switch by Ethernet:

```bash
ssh minhcluster@10.0.0.1 "mkdir -p /clusterfs/aero_evolve"
scp evolve.html aero_evolve.py evolve.sh minhcluster@10.0.0.1:/clusterfs/aero_evolve/
```

(or `vim` the files in directly on the login node.)

**b) Random run each time, fixed run when you ask for it (apply once):**

```bash
cd /clusterfs/aero_evolve
sed -i 's|^rng = np.random.default_rng(1234 + rank)|seed = int(sys.argv[4]) if len(sys.argv) > 4 else int(time.time() * 1000) % 1000003\nrng = np.random.default_rng(seed + rank)|' aero_evolve.py
sed -i 's|2400 30$|2400 30 ${SEED}|' evolve.sh
grep -n "seed\|SEED" aero_evolve.py evolve.sh      # both edits should show
```

Without a seed, every run is different. With `SEED=1`, the same rank count gives the same run, which is what you want for timed comparisons.

**c) Check the LED service on the compute nodes** (the bars pulse while the job runs):

```bash
for h in picluster-node0{1..4}; do ssh $h "systemctl is-active led-load"; done   # four lines: active
```

---

## 2. Getting the page online (over Ethernet, no Tailscale)

The login node is the gateway of the cluster LAN (`10.0.0.1` on `eth0`), so any laptop plugged into the cluster switch can reach it directly.

**a) Serve the folder** on the login node:

```bash
cd /clusterfs/aero_evolve && python3 -m http.server 8001
```

To keep it running after you close the terminal:

```bash
nohup python3 -m http.server 8001 --directory /clusterfs/aero_evolve > /dev/null 2>&1 &
pkill -f "http.server 8001"        # stops it later
```

**b) Connect the demo laptop.** Plug it into the cluster switch. The login node hands out `10.0.0.x` addresses by DHCP,
so the laptop gets one automatically (check with `ip a` or `ifconfig`). If it does not, set it manually to `10.0.0.50/24` with gateway `10.0.0.1`.

**c) Open the page**, typing the full address including `http://`:

```
http://10.0.0.1:8001/evolve.html
```

Use the IP address. The name `picluster-login` only resolves on the cluster nodes, not on your laptop.
Without `http://`, some browsers try HTTPS first; the server prints a few `400 Bad request` lines and then the browser falls back. This is harmless.

Before a job runs, the page says **"Waiting for the cluster…"** and the server log shows `404` for `best.json`. This is expected.

---

## 3. Before the demo (5 minutes)

On `picluster-login`:

```bash
sinfo                                              # 4 nodes idle (if not: sudo scontrol update nodename=picluster-node0[1-4] state=resume)
for h in picluster-node0{1..4}; do ssh $h "systemctl is-active led-load; df -h /clusterfs | tail -1"; done   # active + mounted
cd /clusterfs/aero_evolve
scancel -u $USER                                   # clear any old job
rm -f best.json evo-*.out                          # clean slate
```

Open the page on the demo laptop and hard-refresh (Ctrl+Shift+R). It should show "Waiting for the cluster…".
Keep a second terminal on the login node for SLURM commands.

---

## 4. Running it

**Animated run for the audience** (about a minute or two; `PACE` stretches each generation to at least that many seconds so people can watch):

```bash
cd /clusterfs/aero_evolve
PACE=0.8 sbatch -J evo-16 --nodes=4 --ntasks=16 evolve.sh
squeue
```

**Timed comparison** (no `PACE`, same seed, same total work: the only thing that changes is the number of ranks):

```bash
SEED=1 sbatch -J evo-4  --nodes=1 --ntasks=4  evolve.sh
SEED=1 sbatch -J evo-16 --nodes=4 --ntasks=16 evolve.sh
cat evo-4-*.out evo-16-*.out
```

```
speedup    = wall_4 / wall_16      (ideal = 4: 4x the cores on 4x the nodes)
efficiency = speedup / 4
```

| Run | Ranks | Nodes | Wall time (s) |
|---|---|---|---|
| evo-4 | 4 | 1 | |
| evo-16 | 16 | 4 | |

The total population (2400) and generations (30) are fixed, so more ranks means each island does less work.
Both runs should print a similar best wing, but not exactly identical: the islands differ with the rank count.
If the times are too short to compare, raise `2400` in `evolve.sh`.

---

## 5. How to explain it to people (about 5 minutes)

**1. Hook (1 min).** Open the page. *"Can you design the best wing? You want it to take off in a short distance and fly a long way on one tank."*
Let someone set the **Race the Cluster** sliders to their best guess.

**2. The idle cluster (30 s).** Run `sinfo` to show four idle nodes. The page says "Waiting for the cluster…" and the LED matrices are quiet.

**3. Launch (30 s).** Submit the 16-rank job. *"I'm handing the job to a scheduler called SLURM. It decides which nodes run it."*

**4. Watch (1 to 2 min).** The wing reshapes, the fitness curve climbs, the generation counter ticks and the LED bars pulse. Say:

- *"Each node is an island. It breeds its own population of wings: the best ones have children, with small random changes."*
- *"Every few generations the islands swap their best wings with their neighbour, so good ideas spread."*
- *"Fitness is half range and half short take-off. Short take-off and long range pull in different directions, so the cluster has to find a compromise."*

**5. Challenge (1 min).** When it finishes, let the audience try to beat the cluster. The page shows what percentage of the cluster's best they reached, or "You beat the cluster!".

**6. Optional: the speed proof (1 to 2 min).** Show the 4-rank vs 16-rank times from the timed runs. *"Same work, more nodes, less waiting."*

**7. Real-world link (30 s).** *"This uses a simple formula to score each wing. Real aerofoil design runs a full fluid simulation for every candidate, which is why supercomputers like ASPIRE 2A need thousands of nodes, a scheduler and a fast interconnect."*

### Likely questions

| Question | Answer |
|---|---|
| Does it give the same answer every time? | No. Each run starts from a different random population, but it settles in a similar region, because there is one clear best compromise. With a fixed seed it repeats exactly. |
| Couldn't a laptop do this? | Yes. The problem is small on purpose. The cluster stands in for much bigger searches. |
| Is the airflow real? | No. Lift and drag come from simple aerodynamic formulas, and the streamlines on the page are drawn graphics, not a fluid simulation. |
| Why isn't 16 ranks 4 times faster than 4? | Startup cost, the per-generation waiting and sharing, and the Pis' gigabit network (ASPIRE 2A+ uses 400 Gb/s InfiniBand). |
| What are the LEDs showing? | Each bar is one CPU core's load on that node, so you can see the work spread across the machines. |

---

## 6. Reset between runs

```bash
cd /clusterfs/aero_evolve
scancel -u $USER                     # only if a job is still running
rm -f best.json evo-*.out
```

Then hard-refresh the page (Ctrl+Shift+R). If you only want to run again, you can skip the reset: a new job deletes the old `best.json` itself and the page switches over after generation 1.

---

## 7. Troubleshooting

| Problem | Fix |
|---|---|
| Page stays on "Waiting for the cluster…" | Check `squeue`. If the job ran, read `cat evo-*.out` for errors. The 404s in the server log stop once `best.json` exists. |
| Page not reachable | Check the `http.server` is still running, the laptop has a `10.0.0.x` address, and you typed `http://10.0.0.1:8001/evolve.html` |
| Node shows `down` or `drain` | `sinfo -R`, then `sudo scontrol update nodename=<node> state=resume` |
| 16-rank job fails to start across nodes | Check passwordless SSH between nodes and that `mpirun` works across nodes first |
| `ModuleNotFoundError: mpi4py` or `numpy` | `ssh <node> "sudo apt install -y python3-mpi4py python3-numpy"` |
| Page shows old results after a reset | Hard-refresh (Ctrl+Shift+R) |
| LED bars stay dark | `ssh <node> "sudo systemctl restart led-load"` |
| Run is too quick to watch | Raise `PACE` (e.g. `PACE=1.5`) |
| Timed runs too short to compare | Raise the population `2400` in `evolve.sh` |

---

## Known limitations

- The model is simplified (1,000 kg aircraft, 16 m² wing, thin-aerofoil lift, parabolic drag). It is for intuition, not for real wing design.
- A stalled wing is shown as a warning and a drag penalty, not a flight failure.
- The wind tunnel streamlines on the page are illustrative graphics, not computed airflow.
