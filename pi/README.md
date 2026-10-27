# picluster — Demo Day Guide

A 5-node Raspberry Pi 4B cluster (1 login + 4 compute nodes) running
SLURM-scheduled MPI jobs, with a MAX7219 LED matrix on each compute node
showing live CPU load. This guide is the single thing you need open on
demo day: setup checks, what to run, and what to say.

Cluster: `picluster-login` (10.0.0.1), `picluster-node01`–`node04` (10.0.0.2–.5).
Shared storage: `/clusterfs` (NFS). Login: `minhcluster`.

---

## 1. Before the doors open (10 minutes)

On `picluster-login`:

```bash
sinfo                                              # want: 4 nodes, state=idle
# if any node is down/drain:
sudo scontrol update nodename=picluster-node0[1-4] state=resume

for h in picluster-node0{1..4}; do
  ssh $h "systemctl is-active led-load; df -h /clusterfs | tail -1"
done                                                # want: active + /clusterfs mounted, 4x

ls /clusterfs/pi /clusterfs/led                     # scripts are present

rm -f /clusterfs/pi/pi-*rank-*.out                  # clean slate from last run
squeue                                              # should be empty
```

Check the boards: all four matrices should be showing idle letters
**N S C C** (one per node). If a board is blank, power-cycle that Pi or
`ssh <node> "sudo systemctl restart led-load"`.

Have two terminals open on the login node: one for narrating commands,
one spare for troubleshooting.

---

## 2. The core demo: the π speedup race (5 minutes)

This is the main event. It estimates π by throwing random darts at a
square and counting how many land inside a circle (Monte Carlo method)
— a classic "embarrassingly parallel" problem, good for showing why
more cores = faster answers.

**Opening line to the crowd:**
> "This is a tiny supercomputer — four Raspberry Pis wired together,
> running the same kind of software as national supercomputers like
> ASPIRE 2A. We're going to estimate π by throwing millions of random
> darts at a target, and watch what happens when we use 1 core vs 4."

**Step 1 — one core (no parallelism):**

```bash
cd /clusterfs/pi
sbatch pi_1rank.sh
squeue                      # watch it run
```

Point at the LED board for that node — one bar lights up.

**Step 2 — four cores on one Pi:**

```bash
sbatch pi_4rank.sh
squeue
```

All four bars on that board light up together.

**Step 3 — read the results:**

```bash
cat pi-1rank-*.out pi-4rank-*.out
```

Each line prints something like:
```
pi ~= 3.141593, computed in 24.6 s (19.6 s compute + 5.0 s serial) using 4 rank(s) on 1 node(s)
pi ~= 3.141589, computed in 42.7 s (37.7 s compute + 5.0 s serial) using 1 rank(s) on 1 node(s)
```

Do the math live on screen:
```
speedup    = wall_1rank / wall_4rank
efficiency = speedup / 4
```

**Talking points while it runs:**
- *"Same answer, less time."* Both runs estimate the same π — correctness
  doesn't change, only speed.
- *"Why isn't it exactly 4x faster?"* There's a fixed ~5 s setup cost every
  run pays regardless of core count — that's a miniature version of
  **Amdahl's Law**: the part of a job that can't be parallelised caps your
  maximum speedup, however many cores you throw at it.
- *"This is what a national supercomputer does, just at a much bigger
  scale."* ASPIRE 2A has 768+ compute nodes instead of 4 Pis — same idea,
  thousands of times larger.
  
<img width="452" height="307" alt="image" src="https://github.com/user-attachments/assets/cba3599e-fdfc-459a-b6a7-06cd5239bb5a" />

---

## 3. Optional add-ons (if you have time / a second act)

### Password cracking — the "wow" demo
Closer to linear speedup than π (no fixed serial section), so doubling
ranks visibly halves the time every run — and it's a cybersecurity
hook, not just a performance one. Full script and talking points:
`crack-pwd/README.MD`. Quick version: run `crack_1rank.sh`, then
`crack_4rank.sh`, then `crack_16rank.sh` (all 4 nodes) back to back on a
password you hash live on stage — never a real one.

### Aerofoil design sweep — the interactive one
Lets a visitor design a wing by hand on a laptop (3 sliders), then the
cluster brute-force-searches 600k+ designs for the best one while they
watch. Good for letting someone *drive*. Full setup: `aero/README.md`.
Needs the login node serving `aerofoil.html` over the cluster's Ethernet
switch (`python3 -m http.server 8000` in `/clusterfs/aero`).

---

## 4. If someone asks "but what's it actually *for*?"

> "The exact same pattern — split a huge problem into pieces, hand each
> piece to a different core, add the answers back together — is how real
> supercomputers do weather forecasting, drug discovery, and training AI
> models. These four Pis are a toy version of a machine like ASPIRE 2A,
> which has hundreds of server-grade nodes instead of four hobbyist
> boards, but the scheduling software (SLURM) and the parallel-programming
> model (MPI) are the same ones used in production."

---

## 5. Reset between demo groups

```bash
cd /clusterfs/pi
rm -f pi-*rank-*.out
squeue                      # confirm empty before the next group starts
```

For the aero add-on: `rm -f /clusterfs/aero/aero-*.out /clusterfs/aero/results.json`

---

## 6. Troubleshooting

| Problem | Fix |
|---|---|
| Node shows `down`/`drain` in `sinfo` | `sinfo -R` for the reason, then `sudo scontrol update nodename=<node> state=resume` |
| Job stuck `PD` in `squeue` | Check `sinfo` — likely a down node holding up the partition |
| LED board blank or stuck | `ssh <node> "sudo systemctl restart led-load"` |
| LED board not showing N/S/C/C at idle | `systemctl is-active led-load` on that node; redeploy the script if it crashed |
| `.out` file missing / job vanished from queue instantly | `cat` the file anyway — SLURM often logs the error there (e.g. missing `/clusterfs` mount) |
| Run looks too fast to see the speedup clearly | Bump the sample count: edit `pi_montecarlo.py`'s `DEFAULT_N`, or pass a bigger number as an arg in the `.sh` scripts |
| SSH to a node hangs | Check that node's Ethernet cable / power; `ping 10.0.0.<n>` from the login node |

---

## 7. Quick reference

| Node | IP | Role |
|---|---|---|
| picluster-login | 10.0.0.1 | Scheduler, NFS server, internet gateway |
| picluster-node01 | 10.0.0.2 | Compute — LED: **N** |
| picluster-node02 | 10.0.0.3 | Compute — LED: **S** |
| picluster-node03 | 10.0.0.4 | Compute — LED: **C** |
| picluster-node04 | 10.0.0.5 | Compute — LED: **C** |

Shared files: `/clusterfs/pi` (π demo), `/clusterfs/crack` (password demo),
`/clusterfs/aero` (aerofoil demo), `/clusterfs/led` (LED display source).
