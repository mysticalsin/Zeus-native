#!/usr/bin/env bash
# End-to-end checks against the built app, with nothing of yours touched:
#   unit tests → extension typecheck → bundle → the real bridge + extension in an isolated Chrome
#   for Testing profile (served fixture page) → hook merge on a copy of ~/.claude/settings.json →
#   real claude sessions approved and denied in the notch (throwaway project, project-level hooks)
#   → real Claude turns that must emit the right action tags.
# The approval checks press the notch buttons through Accessibility, so the terminal running this
# needs Accessibility access.
# Needs: scripts/bundle.sh first; Playwright's Chrome for Testing (npx playwright install chromium).
set -uo pipefail
cd "$(dirname "$0")/.."
# Isolated support folder and socket: a ZEUS you are running (and its hooks) is never touched.
export ZEUS_SUPPORT_DIR="${ZEUS_SUPPORT_DIR:-$(mktemp -d /tmp/zeus-e2e.XXXXXX)}"
mkdir -p "$ZEUS_SUPPORT_DIR/bin"
APP="build/Zeus.app"; Z="$APP/Contents/MacOS/Zeus"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  \033[32m✔\033[0m %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  \033[31m✘\033[0m %s\n     %s\n' "$1" "$2"; }
check(){ # name, command output, expected substring
  if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "got: ${2:0:300}"; fi; }

echo "Unit tests"
out=$(scripts/test.sh 2>&1 | grep -E "Test run with"); check "swift tests" "$out" "passed"
echo "Extension"
out=$(cd extension && npm run -s typecheck 2>&1 && echo TYPES_OK); check "typecheck" "$out" "TYPES_OK"

echo "App bundle"
check "icon in bundle" "$(ls $APP/Contents/Resources)" "AppIcon.icns"
check "extension in bundle" "$(ls $APP/Contents/Resources/ChromeExtension)" "popup.html"
check "signature" "$(codesign --verify --strict $APP 2>&1 && echo SIGNED)" "SIGNED"

echo "Chrome bridge (isolated Chrome for Testing profile)"
CFT=$(find "$HOME/Library/Caches/ms-playwright" -maxdepth 4 -name "Google Chrome for Testing.app" 2>/dev/null | sort | tail -1)
if [[ -z "$CFT" ]]; then
  bad "Chrome for Testing" "not found: run 'npx playwright install chromium'"
else
  WORK=$(mktemp -d); PROFILE="$WORK/profile"; mkdir -p "$PROFILE/NativeMessagingHosts"
  cat > "$PROFILE/NativeMessagingHosts/com.zeus.bridge.json" <<JSON
{"name":"com.zeus.bridge","description":"ZEUS e2e","path":"$PWD/$APP/Contents/Helpers/zeus-bridge","type":"stdio",
 "allowed_origins":["chrome-extension://dkpclhaealkdnnihlccglmonmmjfjobe/"]}
JSON
  PORT=$((20000 + RANDOM % 20000))
  python3 -I -m http.server "$PORT" --bind 127.0.0.1 --directory Tests/e2e >/dev/null 2>&1 & HTTP=$!
  "$CFT/Contents/MacOS/Google Chrome for Testing" --headless=new --user-data-dir="$PROFILE" \
    --no-first-run --disable-gpu --load-extension="$PWD/$APP/Contents/Resources/ChromeExtension" \
    "http://127.0.0.1:$PORT/fixture.html" >"$WORK/chrome.log" 2>&1 & CHROME=$!
  for _ in $(seq 1 30); do $Z --chrome ping >/dev/null 2>&1 && break; sleep 1; done
  chrome() { $Z --chrome "$@" 2>&1; }
  # Production mutations require the exact tab/document selected before consent. These fixture
  # calls have no approval UI, but use the same binding instead of an unbound active-tab write.
  chrome_bound() {
    local target params
    target=$(chrome page.target) || return 1
    params=$(python3 -I -c 'import json,sys; p=json.loads(sys.argv[1]); t=json.loads(sys.argv[2]); p["pageTarget"]=t.get("result", t); print(json.dumps(p))' "$2" "$target") || return 1
    chrome "$1" "$params"
  }

  check "extension answers ping"      "$(chrome ping)" '"pong":true'
  check "reads the active tab"        "$(chrome page.context)" "ZEUS end-to-end fixture"
  check "lists links and buttons"     "$(chrome page.context)" '"Sign in"'
  check "clicks by label"             "$(chrome_bound page.click '{"text":"Sign in"}')" '"clicked"'
  check "click took effect"           "$(chrome page.context)" "Signed in!"
  check "missing control is reported" "$(chrome_bound page.click '{"text":"Nope"}')" 'Nothing called'
  check "types and submits"           "$(chrome_bound page.type '{"target":"Search","text":"zeus app","submit":true}')" '"submitted":true'
  check "submit took effect"          "$(chrome page.context)" "Searched: zeus app"
  check "refuses password fields"     "$(chrome_bound page.type '{"target":"Password","text":"x"}')" "password or payment"
  check "rejects non-web links"       "$(chrome tab.open '{"url":"file:///etc/hosts"}')" "Only http"
  check "opens a tab"                 "$(chrome tab.open "{\"url\":\"http://127.0.0.1:$PORT/fixture.html?second\"}")" '"tabId"'
  check "new tab is active"           "$(chrome page.context)" "fixture.html?second"
  check "lists tabs"                  "$(chrome tabs.list)" "?second"
  check "unknown command rejected"    "$(chrome nope.nope)" "nope.nope"

  kill "$CHROME" "$HTTP" 2>/dev/null; wait "$CHROME" 2>/dev/null
  sleep 1
  check "bridge exits with Chrome"    "$(pgrep -f "$APP/Contents/Helpers/zeus-bridge" || echo gone)" "gone"
  check "disconnected is reported"    "$(chrome ping)" "isn't connected"
  rm -rf "$WORK"
fi

echo "Claude Code approvals"
SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  WORK=$(mktemp -d); cp "$SETTINGS" "$WORK/orig.json"; cp "$SETTINGS" "$WORK/settings.json"
  ZEUS_CLAUDE_SETTINGS="$WORK/settings.json" $Z --install-hooks >/dev/null
  ZEUS_CLAUDE_SETTINGS="$WORK/settings.json" $Z --install-hooks >/dev/null   # twice: no duplicates
  check "merge keeps your hooks (on a copy)" "$(python3 -I Tests/e2e/hooks_check.py "$WORK/orig.json" "$WORK/settings.json")" "MERGE_OK"
  ZEUS_CLAUDE_SETTINGS="$WORK/settings.json" $Z --uninstall-hooks >/dev/null
  same=$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))==json.load(open(sys.argv[2])))" "$WORK/orig.json" "$WORK/settings.json")
  check "disconnect restores it exactly" "$same" "True"
  rm -rf "$WORK"
fi

AX="$(mktemp -d)/axtree"; swiftc -O Tests/e2e/axtree.swift -o "$AX" 2>/dev/null
cp "$APP/Contents/Helpers/zeus-hook" "$ZEUS_SUPPORT_DIR/bin/"
if pgrep -xq Zeus; then bad "isolated app" "another ZEUS is running; the notch checks need it closed"; fi
"$PWD/$Z" >"$ZEUS_SUPPORT_DIR/app.log" 2>&1 & APPPID=$!
for _ in $(seq 1 30); do [[ -S "$ZEUS_SUPPORT_DIR/zeus.sock" ]] && break; sleep 0.5; done

echo "zeus CLI (isolated socket)"
ZC="$APP/Contents/Helpers/zeus"
check "zeus status answers"        "$($ZC status 2>&1)" "socket: $ZEUS_SUPPORT_DIR/zeus.sock"
check "zeus status --json"         "$($ZC status --json 2>&1)" '"ok":true'
check "typed turn round trip"      "$($ZC --quiet "what time is it? one short sentence" 2>&1; echo "exit=$?")" "exit=0"
check "task is listed as done"     "$($ZC tasks 2>&1)" "done"
check "usage error exits 2"        "$($ZC --bogus >/dev/null 2>&1; echo "exit=$?")" "exit=2"
check "unknown cancel exits 1"     "$($ZC cancel nope >/dev/null 2>&1; echo "exit=$?")" "exit=1"
approval_run() { # $1 = button to press; prints whether the command ran
  local project; project=$(mktemp -d); mkdir -p "$project/.claude"
  python3 -I - "$project" <<'PY'
import json, os, sys
hook = os.environ["ZEUS_SUPPORT_DIR"] + "/bin/zeus-hook"
command = f"/bin/sh -c '[ -x \"{hook}\" ] && \"{hook}\" --source claude-code || true'"
handler = lambda waits: {"type": "command", "command": command, **({"timeout": 120} if waits else {"async": True})}
events = [("SessionStart", "", 0), ("UserPromptSubmit", "", 0), ("PreToolUse", "*", 0), ("PermissionRequest", "*", 1), ("Stop", "", 0), ("SessionEnd", "", 0)]
json.dump({"hooks": {e: [{"matcher": m, "hooks": [handler(w)]}] for e, m, w in events}}, open(sys.argv[1] + "/.claude/settings.json", "w"))
PY
  (cd "$project" && claude -p "Use the Bash tool to run exactly: echo zeus-e2e-ok > proof.txt. Then reply DONE." </dev/null >out.txt 2>&1) & local run=$!
  local pressed=no
  for _ in $(seq 1 60); do "$AX" - "$1" 2>/dev/null | grep -q "PRESS true" && { pressed=yes; break; }; sleep 1; done
  wait $run
  echo "pressed=$pressed ran=$([[ -f "$project/proof.txt" ]] && echo yes || echo no)"
  rm -rf "$project"
}
check "real claude session: Approve in the notch runs it" "$(approval_run Approve)" "pressed=yes ran=yes"
check "real claude session: Deny in the notch blocks it"  "$(approval_run Deny)"    "pressed=yes ran=no"

echo "Brain (real claude CLI)"
out=$($Z --ask "open github in chrome" 2>&1); check "emits browser.open" "$out" "browserOpen"
out=$($Z --ask "ask chatgpt to write a haiku about storms" 2>&1); check "emits panel.open for chatgpt" "$out" '"chatgpt"'

kill "$APPPID" 2>/dev/null; wait "$APPPID" 2>/dev/null
check "zeus with ZEUS closed exits 3" "$($ZC status >/dev/null 2>&1; echo "exit=$?")" "exit=3"

echo; echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
