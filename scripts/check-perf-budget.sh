#!/bin/bash
# Performance budget gate: idle CPU under 1% average and memory under 150 MB for a running ZEUS,
# and no Ollama or Kev helper processes running by default. Read-only: samples with ps/top,
# never launches, quits or signals anything.
#   PID=<pid> SECONDS_IDLE=60 scripts/check-perf-budget.sh
set -uo pipefail
SAMPLE="${SECONDS_IDLE:-60}"
LOG="${LOG:-../topbar-proof/perf-budget.log}"
pid="${PID:-$(pgrep -f 'zeus-wt/topbar/build/Zeus.app/Contents/MacOS/Zeus' | head -1)}"
[ -n "$pid" ] || { echo "no ZEUS from this worktree running; pass PID=" | tee "$LOG"; exit 2; }
exe="$(ps -o comm= -p "$pid")"
echo "perf budget $(date '+%F %T %Z') pid=$pid exe=$exe window=${SAMPLE}s" | tee "$LOG"
# top -l N -s 1 gives per-second CPU; the first sample is cumulative, so drop it.
cpu="$(top -l $((SAMPLE + 1)) -s 1 -pid "$pid" -stats cpu | awk 'f&&/^[0-9.]+$/{s+=$1;n++} /^%CPU/{f=1} END{if(n>1) printf "%.2f", s/n; else print "nan"}')"
mem="$(footprint "$pid" 2>/dev/null | awk '/phys_footprint:/{print $2, $3; exit}')"
[ -n "$mem" ] || mem="$(ps -o rss= -p "$pid" | awk '{printf "%.0f MB", $1/1024}')"
mem_mb="$(echo "$mem" | awk '{v=$1; if ($2 ~ /GB/) v*=1024; if ($2 ~ /KB/) v/=1024; printf "%.0f", v}')"
helpers="$(pgrep -fl 'ollama|kev' | grep -v pgrep || true)"
echo "idle CPU avg: ${cpu}% (budget < 1%)" | tee -a "$LOG"
echo "memory footprint: ${mem_mb} MB (budget < 150 MB)" | tee -a "$LOG"
echo "helper processes: ${helpers:-none} (budget none)" | tee -a "$LOG"
ok=1
awk -v c="$cpu" 'BEGIN{exit !(c+0 < 1)}' || ok=0
[ "$mem_mb" -lt 150 ] || ok=0
[ -z "$helpers" ] || ok=0
echo "result: $([ $ok = 1 ] && echo PASS || echo FAIL)" | tee -a "$LOG"
[ $ok = 1 ]
