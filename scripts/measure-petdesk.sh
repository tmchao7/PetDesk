#!/bin/zsh
# Measure PetDesk idle CPU% and RSS (MB) over a fixed window.
# Usage: scripts/measure-petdesk.sh <app-path> [sample-seconds] [settle-seconds]
set -euo pipefail

APP="$1"
SAMPLES="${2:-60}"
SETTLE="${3:-15}"

pkill -x PetDesk 2>/dev/null || true
sleep 1
open "$APP"
sleep "$SETTLE"  # let launch, sprite load, and window settle

PID="$(pgrep -x PetDesk | head -1)"
if [[ -z "$PID" ]]; then
  echo "ERROR: PetDesk not running after launch" >&2
  exit 1
fi

cpu_sum=0.0
rss_sum=0.0
rss_peak=0
count=0

for _ in $(seq 1 "$SAMPLES"); do
  read -r cpu rss <<< "$(ps -o %cpu=,rss= -p "$PID" | awk '{print $1, $2}')"
  cpu_sum=$(echo "$cpu_sum + $cpu" | bc -l)
  rss_mb=$((rss / 1024))
  rss_sum=$(echo "$rss_sum + $rss_mb" | bc -l)
  if (( rss_mb > rss_peak )); then rss_peak=$rss_mb; fi
  count=$((count + 1))
  sleep 1
done

avg_cpu=$(echo "scale=2; $cpu_sum / $count" | bc -l)
avg_rss=$(echo "scale=0; $rss_sum / $count" | bc -l)

echo "samples=$count"
echo "avg_cpu_pct=$avg_cpu"
echo "avg_rss_mb=$avg_rss"
echo "peak_rss_mb=$rss_peak"
