#!/bin/bash
# sysbench CPU benchmark for the login node only.
#   ./bench_cpu_login.sh                  # defaults: threads 1 2 4, prime 20000, 10 s each
#   ./bench_cpu_login.sh "1 4" 30000 20   # optional: thread list, max prime, seconds per run

THREADS=${1:-"1 2 4"}
PRIME=${2:-20000}
SECS=${3:-10}
OUT=$HOME/cpu-login-$(date +%Y%m%d-%H%M%S).txt

command -v sysbench >/dev/null || { sudo apt update && sudo apt install -y sysbench; }

{
  echo "host: $(hostname)   prime=$PRIME   time=${SECS}s per run"
  echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
  echo "before: $(vcgencmd measure_temp) $(vcgencmd get_throttled)"
  for t in $THREADS; do
    echo "== threads=$t"
    sysbench cpu --cpu-max-prime=$PRIME --threads=$t --time=$SECS run \
      | grep -E 'events per second|avg:|95th'
  done
  echo "after:  $(vcgencmd measure_temp) $(vcgencmd get_throttled) $(vcgencmd measure_clock arm)"
} | tee "$OUT"

echo; echo "Saved to $OUT"
