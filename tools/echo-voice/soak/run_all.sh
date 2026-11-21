#!/bin/bash
# Echo soak driver (harness v2). Everything stays inside $B. Stages: install | download | smoke | faults | runs
# Retries 0: every case/run executes at most once; its outcome (pass or fail) is recorded in runs/STATUS.tsv and
# a second invocation skips anything already recorded instead of re-running it.
set -u
B=/Users/tony/echo-haru-soak; cd "$B" || exit 1
export TMPDIR=$B/tmp HF_HOME=$B/hf HF_HUB_OFFLINE=1 PIP_CACHE_DIR=$B/pipcache XDG_CACHE_HOME=$B/cache
REV=8d6e83bcd3701a76fc27a764965665da1df7da78
SHA=ad2c3534ef6bd88525e22e5da3ac4fb739368406bf3b1c852cbafbade647c0fa
PY=$B/venv/bin/python
ST=$B/runs/STATUS.tsv
COMMON="--barge-in-every 5 --sample-seconds 45 --min-free-gib 6"
mkdir -p runs tmp
[ -f "$ST" ] || printf "id\texit\twall_s\tstart\tend\tnote\n" > "$ST"
ts() { date "+%Y-%m-%d %H:%M:%S"; }
freeok() { local f=$(df -k ~ | awk 'NR==2{print $4}'); echo "[$(ts)] free_GiB=$((f/1024/1024))"; [ "$f" -gt $((6*1024*1024)) ]; }
recorded() { awk -F'\t' -v id="$1" '$1==id{f=1} END{exit !f}' "$ST"; }
record() { printf "%s\t%s\t%s\t%s\t%s\t%s\n" "$1" "$2" "$3" "$4" "$5" "${6:-}" >> "$ST"; }
t0file() { [ -f runs/.t0 ] || date +%s > runs/.t0; cat runs/.t0; }
case "$1" in
install)
  /Users/tony/.local/bin/python3.12 -m venv venv && ./venv/bin/pip install --require-hashes --no-deps -r requirements.txt \
    && ./venv/bin/python -c "import haru_mlx, mlx.core as mx; print('haru_mlx', haru_mlx.__version__, 'mlx', mx.__version__)" \
    && { ./venv/bin/pip list 2>/dev/null | grep -i torch && echo "TORCH PRESENT" || echo "no torch"; }
  echo "install exit=$?";;
smoke)
  recorded SMOKE && { echo "SMOKE already recorded (retries 0)"; exit 0; }
  $PY haru_soak.py selftest > runs/SELFTEST.log 2>&1 || { tail -5 runs/SELFTEST.log; exit 5; }
  tail -1 runs/SELFTEST.log
  [ -d script_en ] || $PY haru_soak.py make-script --lang en --out script_en || exit 6
  [ -d script_fr ] || $PY haru_soak.py make-script --lang fr --out script_fr || exit 6
  freeok || exit 3
  s=$(date +%s); S0=$(ts)
  $PY haru_soak.py run --backend haru --model Haru-4B --quantize 8 --script script_en --system-prompt-file card_en.txt \
     --minutes 1 --seed 0 --kv-window 256 --watchdog --reanchor-minutes 0.5 --barge-in-every 3 --sample-seconds 10 --out runs/SMOKE > runs/SMOKE.log 2>&1
  rc=$?; record SMOKE $rc $(( $(date +%s) - s )) "$S0" "$(ts)"
  echo "smoke exit=$rc"; tail -5 runs/SMOKE.log;;
faults)
  recorded FAULTS && { echo "FAULTS already recorded (retries 0)"; exit 0; }
  freeok || exit 3; t0file >/dev/null
  s=$(date +%s); S0=$(ts)
  $PY haru_soak.py faults --backend haru --model Haru-4B --quantize 8 --script script_en --system-prompt-file card_en.txt \
     --minutes 1.5 --stall-s 5 --out runs/faults 2>&1 | tee runs/FAULTS.log
  rc=${PIPESTATUS[0]}; record FAULTS $rc $(( $(date +%s) - s )) "$S0" "$(ts)" "see runs/faults/faults.json";;
runs)
  START=$(t0file); BUDGET=$((150*60))      # budget counts faults + runs (smoke excluded)
  run() { local id=$1 mins=$2 lang=$3; shift 3
    recorded "$id" && { echo "[$(ts)] $id already recorded (retries 0), not re-running"; return; }
    freeok || { record "$id" "" 0 "$(ts)" "$(ts)" "SKIP disk under 6 GiB"; echo "ABORT: under 6 GiB"; exit 3; }
    local t0=$(date +%s) s0=$(ts); echo "[$s0] start $id ($mins min $lang) flags: $*"
    $PY haru_soak.py run --backend haru --model Haru-4B --quantize 8 --script script_$lang --system-prompt-file card_$lang.txt \
       --minutes $mins --seed 0 $COMMON "$@" --out runs/$id > runs/$id.log 2>&1
    local rc=$?; record "$id" $rc $(( $(date +%s) - t0 )) "$s0" "$(ts)"
    echo "[$(ts)] end $id exit=$rc wall_s=$(( $(date +%s) - t0 ))"; }
  run A60 60 en
  run A30fr 30 fr
  run C10-dryoff 10 en --dry off
  run C10-t05 10 en --temperature 0.5
  run C10-t09p09 10 en --temperature 0.9 --top-p 0.9
  run C10-kv1024 10 en --kv-window 1024
  run C10-dry12 10 en --dry-multiplier 1.2
  EL=$(( $(date +%s) - START )); PRED=$(( 60*60*65/100 + 120 ))
  if ! recorded B60 && [ $((EL + PRED)) -gt $BUDGET ]; then
    echo "[$(ts)] SKIP B60: elapsed ${EL}s + predicted ${PRED}s > budget ${BUDGET}s"; record B60 "" 0 "$(ts)" "$(ts)" "SKIP budget: elapsed ${EL}s + predicted ${PRED}s > ${BUDGET}s"
  else run B60 60 en --kv-window 4096 --reanchor-minutes 15 --watchdog; fi
  echo "[$(ts)] ALLDONE total_s=$(( $(date +%s) - START ))";;
pack)
  # small, copy-friendly bundle; per-file sha256 manifest computed on the Mac for cross-checking after CopyToBox
  cd runs && find . -type f ! -name MAC_MANIFEST.sha256 ! -name '.t0' | sort | xargs shasum -a 256 > MAC_MANIFEST.sha256 && cd .. \
    && tar czf echo-haru-soak-results.tgz runs && shasum -a 256 echo-haru-soak-results.tgz;;
esac
