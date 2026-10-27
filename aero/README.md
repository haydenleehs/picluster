# Aerofoil Design Demo on the Raspberry Pi Cluster

Design a wing by hand in the browser, then let the cluster search 600k+ designs
for the best one. Shows why researchers use a job scheduler and parallel
computing (the same idea as ASPIRE 2A, at miniature scale).

| Part | Where it runs | What it does |
|---|---|---|
| `aerofoil.html` | Your browser | Game: 3 sliders (angle, camber, thickness), lift/drag, take-off + range animation |
| `aero_sweep.py` | Pi cluster (MPI via SLURM) | Brute-force sweep of every design, reports best take-off, best range and best all-rounder |
| `aero.sh` | Login node | SLURM job script, rank count set at submit time |

Files live in `/clusterfs/aero/` (shared by all nodes over NFS).

---

## 1. Before the demo (5 minutes)

On `picluster-login`:

```bash
sinfo                                              # 4 nodes idle (if not: sudo scontrol update nodename=picluster-node0[1-4] state=resume)
for h in picluster-node0{1..4}; do ssh $h "systemctl is-active led-load; df -h /clusterfs | tail -1"; done   # active + mounted
ls /clusterfs/aero                                 # aerofoil.html aero_sweep.py aero.sh
rm -f /clusterfs/aero/aero-*.out /clusterfs/aero/results.json   # clean slate
cd /clusterfs/aero && python3 -m http.server 8000  # leave running in a spare terminal
```

Open `http://10.0.0.1:8000/aerofoil.html` on the demo laptop (plugged into the cluster switch by Ethernet, see section 6).
Keep a second terminal on the login node for SLURM commands.

---

## 2. Demo script (about 5 minutes)

**Step 1: Play it by hand (1 min).**
Move the sliders. Point out: more angle and camber means more lift but more drag; too much angle stalls;
many designs are good for take-off *or* range, not both. Press **Fly this design** to show the animation.
Ask the audience: *"Can you find the best wing in 30 seconds?"*

**Step 2: Show the cluster idle (30 s).**
```bash
sinfo          # 4 nodes idle
```
The LED bars on the compute nodes are flat.

**Step 3: Submit the sweep (1 min).**
```bash
cd /clusterfs/aero
sbatch -J aero-4  --nodes=1 --ntasks=4  aero.sh
sbatch -J aero-16 --nodes=4 --ntasks=16 aero.sh
squeue                                  # watch them run
```
The 4-rank job fills the four bars on one node (all 4 cores of one Pi). The 16-rank job fills the bars on all four nodes.

**Step 4: Read the result (1 min).**
```bash
cat aero-4-*.out aero-16-*.out
```
Both files give the **same designs** (correct: parallel does not change the answer) but the **wall time** differs.

```
speedup    = wall_4 / wall_16      (ideal = 4, since 4x the cores on 4x the nodes)
efficiency = speedup / 4
```

| Run | Ranks | Nodes | Wall time (s) |
|---|---|---|---|
| aero-4 | 4 | 1 | |
| aero-16 | 16 | 4 | |

**Step 5: Take the answer back to the game (1 min).**
Copy the "best all-rounder" line (angle, camber, thickness) into the sliders and press **Fly**.
Compare with the design the audience found by hand.

**Step 6: Tie it to real research (30 s).**
This sweep uses a simple formula per design. Real aerofoil design runs a full fluid simulation (OpenFOAM) per design,
which is why centres like ASPIRE 2A need thousands of nodes, a scheduler (SLURM) and a fast interconnect.

---

## 3. Talking points

- **Why the same answer, less time?** Each rank takes every 16th design (`designs[rank::size]`). Rank 0 gathers the results.
- **Why isn't speedup a perfect 4x (4 cores on 1 node vs 16 cores on 4 nodes)?** Startup cost, the final gather, and the Pis' gigabit network (ASPIRE 2A+ uses 400 Gb/s InfiniBand).
- **Is this sweep too small for a cluster?** Yes, a laptop would finish it quickly. It stands in for much bigger problems.

---

## 4. Troubleshooting

| Problem | Fix |
|---|---|
| Node shows `down` or `drain` | `sinfo -R`, then `sudo scontrol update nodename=<node> state=resume` |
| 16-rank job fails to start across nodes | Check passwordless SSH between nodes and that `mpirun` works with `-n 4` on each node first |
| Timings are all about the same | Sweep too small. Raise the refinement in `aero.sh` (`aero_sweep.py 1` to `2`), but watch RAM: every rank holds the full design list |
| Job killed / out of memory | Use refinement 1 (about 620k designs) |
| LED bars stay dark | `ssh <node> "sudo systemctl restart led-load"` |
| **Fly this design** does nothing | Hard refresh (Ctrl+Shift+R); check the browser console (F12) for errors |
| Page not reachable | Check the `http.server` terminal is still running, the laptop is on the cluster switch (has a `10.0.0.x` address) and you used `http://10.0.0.1:8000/aerofoil.html` |

---

## 5. Reset between runs

```bash
rm -f /clusterfs/aero/aero-*.out /clusterfs/aero/results.json
scancel -u $USER
```

## Known limitations

- The model is simplified (1,000 kg aircraft, 16 m² wing). It is for intuition, not for real wing design.
- A stalled wing is shown as a warning and a drag penalty, not a flight failure.

---

## 6. Putting it online (over Ethernet, no Tailscale)

The login node is the gateway of the cluster LAN (`10.0.0.1` on `eth0`), so any laptop plugged into the cluster
switch can reach it directly.

**a) Get the files onto the login node.** From the laptop on the same Ethernet network:

```bash
scp aerofoil.html aero_sweep.py aero.sh minhcluster@10.0.0.1:/clusterfs/aero/
```

(or `vim` them in directly on the login node, or `git pull` if you use the repo.)

**b) Serve the page** on the login node:

```bash
cd /clusterfs/aero && python3 -m http.server 8000
```

To keep it running after you close the terminal: `nohup python3 -m http.server 8000 --directory /clusterfs/aero > /dev/null 2>&1 &`
(stop it later with `pkill -f "http.server 8000"`).

**c) Connect the demo laptop.** Plug it into the cluster switch. The login node hands out `10.0.0.x` addresses by DHCP
on that port, so the laptop gets one automatically (check with `ip a` or `ifconfig`). Then open:

```
http://10.0.0.1:8000/aerofoil.html
```

Use the IP address. The name `picluster-login` only resolves on the cluster nodes, not on your laptop.
If the laptop does not get an address, set it manually to `10.0.0.50/24` with gateway `10.0.0.1`.
