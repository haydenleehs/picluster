# picluster — Pre-Demo Check README

Quick checklist to run on `picluster-login` before doors open. Covers getting
the cluster into a known-good state; see `runbook.md` for the live demo script
itself.

---

## 1. Cluster is up

```bash
sinfo
```

Expect:

```
PARTITION AVAIL  TIMELIMIT  NODES  STATE NODELIST
cluster*     up   infinite      1   idle picluster-node0[1-4]
```

If not idle:

```bash
sinfo -R
sudo scontrol update nodename=picluster-node01 state=resume
```

## 2. Shared filesystem is mounted

```bash
ssh picluster-node01 "findmnt /clusterfs"
```

Expect:

```
TARGET     SOURCE                     FSTYPE OPTIONS
/clusterfs picluster-login:/clusterfs nfs4   rw,...
```

If it prints nothing, mount it:

```bash
ssh picluster-node01 "sudo mount -a && findmnt /clusterfs"
```

## 3. Files are present

```bash
ls /clusterfs/pi
```

Expected:

```
pi_montecarlo.py  pi-1rank.sh  pi-4rank.sh  pi-4rank-test.sh
```

## 4. SLURM smoke test

```bash
srun -N1 -n4 hostname
sbatch pi-4rank-test.sh

rm -f /clusterfs/pi/*.out
```

## 5. LED matrix test

```bash
for h in $NODES; do ssh $h "systemctl is-active led-load"; done   # expect: active x4
```

If any node prints `failed`/`inactive`:

```bash
ssh picluster-node0X "sudo systemctl restart led-load && journalctl -u led-load -n 5"
```

---

## Troubleshooting: nodes stuck / not responding

Symptom during step 1 or 4: `srun`/`sbatch` hang with
`Required node not available (down, drained or reserved)`, and `sinfo -Nl`
shows `idle*` (note the asterisk) with reason `Not responding`.

### a) Confirm the reason

```bash
sinfo -Nl
```

`idle*` + `Not responding` means `slurmctld` hasn't heard from `slurmd` on
that node — it's a controller↔compute communication problem, not a job
problem.

### b) Check slurmd is actually running on the compute nodes

```bash
for h in picluster-node0{1..4}; do ssh $h "systemctl is-active slurmd"; done
```

If any are `failed`/`inactive`, check the log:

```bash
ssh picluster-node0X "sudo journalctl -u slurmd -n 50 --no-pager"
```

A fatal error like:

```
error: _xgetaddrinfo: getaddrinfo() failed: Name or service not known: ...
fatal: Unable to bind listen port (6818): Address family not supported by protocol
```

means `slurmd` can't resolve its own hostname against the `NodeName` entry in
`slurm.conf` — an `/etc/hosts` problem, not a SLURM config problem.

### c) Check /etc/hosts and self-resolution on the node

```bash
ssh picluster-node0X "getent hosts \$(hostname)"
```

Should return `10.0.0.X  picluster-node0X`. If empty, `/etc/hosts` is
missing the cluster block — re-add it:

```bash
for h in picluster-node0{1..4}; do
  ssh $h "sudo tee -a /etc/hosts >/dev/null <<'EOF'

# Pi cluster
10.0.0.1   picluster-login
10.0.0.2   picluster-node01
10.0.0.3   picluster-node02
10.0.0.4   picluster-node03
10.0.0.5   picluster-node04
EOF"
done
```

### d) Restart slurmd and recheck

```bash
for h in picluster-node0{1..4}; do ssh $h "sudo systemctl restart slurmd"; done
sleep 3
sinfo -Nl
```

A node that comes back clean shows plain `idle` with reason `none` (no
asterisk). Any node still showing `Not responding` just needs `/etc/hosts`
and `slurmd` rechecked individually (steps b–c) — it clears on its own once
`slurmctld` gets a heartbeat back, so there's no manual `state=resume` step
needed for this particular reason (that command is only valid for nodes in
`DOWN`/`DRAIN`, and returns `Invalid node state specified` otherwise).

### e) Other things worth checking if the above doesn't resolve it

- **Munge auth** (slurmd silently fails to authenticate if this is broken):
  ```bash
  ssh picluster-node01 "munge -n" | unmunge   # must end STATUS: Success (0)
  for h in picluster-node0{1..4}; do ssh $h "systemctl is-active munge"; done
  ```
- **Clock skew** between login and compute nodes:
  ```bash
  date; for h in picluster-node0{1..4}; do ssh $h date; done
  ```
