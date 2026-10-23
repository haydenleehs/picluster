# Password-Cracking Demo (picluster)

A brute-force MD5 cracking demo for the Raspberry Pi HPC cluster. Same
MPI/SLURM pattern as the Monte Carlo π workload, but the speedup is
closer to linear, which makes it a punchier public demo.

---

## How it works

A short password is hashed (MD5). The cluster brute-forces every
possible string of a given length until one hashes to the target. Work
is split across MPI ranks by interleaving the keyspace (rank `r`
checks indices `r, r+size, r+2*size, ...`), so load stays balanced
even if the answer happens to sit near the start. Whichever rank finds
a match broadcasts it to the others so they stop immediately instead
of finishing the whole search.

Doubling the ranks roughly halves the time — unlike the π workload,
there's no fixed serial section, so the scaling story is simpler.

---

## Setup steps

### 1. Write the script

On `picluster-login`:

```bash
mkdir -p /clusterfs/crack
tee /clusterfs/crack/hash_crack.py >/dev/null <<'EOF'
#!/usr/bin/env python3
"""Brute-force MD5 cracker, parallelised with MPI (mpi4py).

Each rank searches an interleaved slice of the keyspace (rank r checks
indices r, r+size, r+2*size, ...) so work stays balanced even if the
answer sits near the start. Ranks periodically check for a "found"
broadcast from whoever wins, same idle-wait spirit as the Ibarrier
pattern used in pi_montecarlo.py.

Usage:
    mpirun -n <ranks> python3 hash_crack.py <target_md5_hash> [length]
"""
import sys
import time
import hashlib
import string
from mpi4py import MPI

ALPHABET    = string.ascii_lowercase
CHECK_EVERY = 20_000      # how often to poll for a "found" signal
POLL        = 0.02


def idx_to_str(i, length, alphabet=ALPHABET):
    base = len(alphabet)
    chars = []
    for _ in range(length):
        i, rem = divmod(i, base)
        chars.append(alphabet[rem])
    return "".join(reversed(chars))


comm = MPI.COMM_WORLD
rank = comm.Get_rank()
size = comm.Get_size()

if len(sys.argv) < 2:
    if rank == 0:
        print("usage: hash_crack.py <target_md5_hash> [length]")
    sys.exit(1)

target = sys.argv[1].lower()
length = int(sys.argv[2]) if len(sys.argv) > 2 else 5
total  = len(ALPHABET) ** length

req = comm.Ibarrier()
while not req.Test():
    time.sleep(POLL)
t_start = MPI.Wtime()

found_req = comm.irecv(source=MPI.ANY_SOURCE, tag=99)
found = None
i = rank
checked = 0
while i < total:
    candidate = idx_to_str(i, length)
    if hashlib.md5(candidate.encode()).hexdigest() == target:
        found = candidate
        for r in range(size):
            if r != rank:
                comm.isend(candidate, dest=r, tag=99)
        break
    i += size
    checked += 1
    if checked % CHECK_EVERY == 0:
        done, msg = found_req.test()
        if done:
            found = msg
            break
        found_req.cancel()
        found_req = comm.irecv(source=MPI.ANY_SOURCE, tag=99)

results = comm.gather(found, root=0)
t_end = MPI.Wtime()

if rank == 0:
    answer = next((r for r in results if r), None)
    wall = t_end - t_start
    if answer:
        print(f"Cracked: '{answer}' in {wall:.2f} s using {size} rank(s)")
    else:
        print(f"No match found in {wall:.2f} s using {size} rank(s)")
EOF
```

### 2. Generate a target hash and test by hand

```bash
python3 -c "import hashlib; print(hashlib.md5('zebra'.encode()).hexdigest())"

ssh picluster-node01 "cd /clusterfs/crack && mpirun -n 4 python3 hash_crack.py <hash> 5"
```

### 3. Calibrate difficulty

| Length | Keyspace (a-z) | 1-rank time   | Use for             |
|--------|-----------------|---------------|----------------------|
| 5      | ~11.9M          | seconds       | quick first pass     |
| 6      | ~309M           | tens of sec–min | the "wow" run       |

Adjust length until the 1-rank run feels slow enough to make the
speedup obvious but not so slow the audience gets bored (aim for
under ~60 s on 1 rank).

### 4. Write job scripts

Three SLURM scripts, identical except rank/node count:

```bash
tee /clusterfs/crack/crack_1rank.sh >/dev/null <<'EOF'
#!/bin/bash
#SBATCH --job-name=crack-1rank
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/crack/%x-%j.out

cd /clusterfs/crack
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 hash_crack.py "$1" "${2:-6}"
EOF

tee /clusterfs/crack/crack_4rank.sh >/dev/null <<'EOF'
#!/bin/bash
#SBATCH --job-name=crack-4rank
#SBATCH --partition=cluster
#SBATCH --nodes=1
#SBATCH --ntasks=4
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/crack/%x-%j.out

cd /clusterfs/crack
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
mpirun -n "$SLURM_NTASKS" python3 hash_crack.py "$1" "${2:-6}"
EOF

tee /clusterfs/crack/crack_16rank.sh >/dev/null <<'EOF'
#!/bin/bash
#SBATCH --job-name=crack-16rank
#SBATCH --partition=cluster
#SBATCH --nodes=4
#SBATCH --ntasks=16
#SBATCH --ntasks-per-node=4
#SBATCH --time=00:10:00
#SBATCH --output=/clusterfs/crack/%x-%j.out

cd /clusterfs/crack
echo "host=$(hostname)  ranks=$SLURM_NTASKS"
srun --mpi=pmix python3 hash_crack.py "$1" "${2:-6}"
EOF

chmod +x /clusterfs/crack/crack_*.sh
```

> The 16-rank script uses `srun --mpi=pmix` instead of `mpirun` so
> SLURM handles cross-node placement directly — check this matches
> whichever launcher you ended up using for multi-node runs of
> `pi_4rank.sh`, and swap it if your setup uses a hostfile instead.

### 5. Submit and compare

```bash
HASH=$(python3 -c "import hashlib; print(hashlib.md5('zebra1'.encode()).hexdigest())")
cd /clusterfs/crack
sbatch crack_1rank.sh "$HASH" 6
sbatch crack_4rank.sh "$HASH" 6
sbatch crack_16rank.sh "$HASH" 6
cat crack-1rank-*.out crack-4rank-*.out crack-16rank-*.out
```

### 6. LED wave

Trigger the existing N-S-C-C wave pattern on job start and on the
"found" broadcast, same as the π demo, so the LEDs animate through
the whole run and sweep on completion.

---

## Why this matters

This demo is worth running over a generic "watch it go fast" demo for
a few reasons:

- **It's the clearest story on the cluster.** The π workload has a
  fixed serial section that caps its speedup (Amdahl's law), so the
  gains flatten out. Password cracking has no such bottleneck — the
  speedup stays close to linear, so doubling ranks visibly halves the
  time every single run. That's the easiest "more cores = more power"
  moment to land with a non-technical audience.
- **It teaches a real security lesson, not just a performance one.**
  "Short passwords are weak" is abstract until you watch a 5-character
  one fall in under a second. Making the weakness visible is more
  convincing than stating it.
- **It connects HPC to cybersecurity directly.** Most visitors think
  of supercomputers as being for weather or physics. Showing that the
  same parallel-computing principle is also how attackers brute-force
  credentials — and how defenders reason about password policy and
  hashing cost — broadens what people think HPC is for.
- **It ties back to your own coursework.** Framing it as "offense and
  defense of cybersecurity" rather than just "cracking passwords" is
  a deliberate choice: it's accurate, it's a stronger hook than a pure
  performance demo, and it signals your program's focus if staff or
  recruiters are in the audience.
- **The ethics framing matters as much as the technical setup.**
  Always crack a password you hashed yourself live on stage, never a
  real credential. That one detail is what keeps the demo
  unambiguously educational instead of looking like you're
  demonstrating an attack on someone's actual secret.

---

## Explaining it to the public

**Opening line:**
> "I just picked a secret password and hashed it — nobody, including
> me right now, knows which of the millions of possible passwords it
> is. Watch the cluster find it."

**Run 1 — single Pi, one core:**
Submit `crack_1rank.sh`. One LED bar lights up. Let it run to
completion so the audience feels the wait.

**Run 2 — one Pi, four cores:**
Submit `crack_4rank.sh`. Four bars light up on one node. Point out the
drop in time on screen.

**Run 3 — all four Pis, sixteen cores:**
Submit `crack_16rank.sh`. All sixteen bars across all four boards
light up together. The answer appears in a fraction of the first
run's time.

**Key talking points:**
- *"More hands searching smaller piles finds the answer faster."*
  Each core only has to check a fraction of the possibilities.
- *"This is why short passwords are weak."* A 5-character password
  falls in seconds; make it longer or mix in symbols and numbers and
  the search space — and crack time — explodes.
- *"This is what real HPC systems do, just bigger."* National
  supercomputers like ASPIRE 2A and 2A+ use the same idea — splitting
  a huge problem across thousands of cores — for things like climate
  modelling, drug discovery, and AI training, not password cracking.
- **Framing note:** always use a password you hashed live on stage,
  never anyone's real password. Pitch it explicitly as a lesson in
  *why weak passwords are risky and how parallel computing applies to
  both attack and defence in cybersecurity* — keeps it clearly
  educational.

**Closing line:**
> "That's the same principle behind everything from weather
> forecasting to training AI models — break a huge problem into
> small pieces, hand each piece to a different core, and put the
> answer back together."
