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
# create /clusterfs/crack/hash_crack.py
# (MPI brute-force script — see repo for full source)
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

- `crack_1rank.sh` — 1 node, 1 task
- `crack_4rank.sh` — 1 node, 4 tasks
- `crack_16rank.sh` — 4 nodes, 16 tasks (4 per node)

Each takes the target hash and length as arguments and calls
`mpirun -n "$SLURM_NTASKS" python3 hash_crack.py "$1" "${2:-6}"`.

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
