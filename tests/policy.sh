#!/usr/bin/env bash
# Tests for codex-quota.py (fake `codexbar`) and sync-claude-md.py (temp config dir). No network.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$ROOT/skills/opus-codex-flow/scripts"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$TMP/bin"
cat > "$TMP/bin/codexbar" <<'FAKE'
#!/usr/bin/env bash
# FAKE_TIER, FAKE_USED, FAKE_ELAPSED (percent of the 7-day window), FAKE_PRIMARY (used %, optional),
# FAKE_PACE=none|expected|wontlast, FAKE_MODE=ok|garbage|dict|nowindow|stale
case "${FAKE_MODE:-ok}" in
  garbage) echo 'not json'; exit 0 ;;
  dict) echo '{"usage": {}}'; exit 0 ;;
esac
python3 -I - <<'PY'
import json, os
from datetime import datetime, timedelta, timezone
mode = os.environ.get("FAKE_MODE", "ok")
window = 7 * 24 * 60
elapsed = float(os.environ["FAKE_ELAPSED"])
left = window * (1 - elapsed / 100)
if mode == "stale":
    left = -60
resets = (datetime.now(timezone.utc) + timedelta(minutes=left)).strftime("%Y-%m-%dT%H:%M:%SZ")
week = {"windowMinutes": window, "usedPercent": float(os.environ["FAKE_USED"]), "resetsAt": resets}
if mode == "nowindow":
    week = {"usedPercent": 5}
entry = {"source": "oauth", "usage": {
    "loginMethod": os.environ["FAKE_TIER"], "secondary": week,
    "primary": ({"windowMinutes": 300, "usedPercent": float(os.environ["FAKE_PRIMARY"]), "resetsAt": resets}
                if os.environ.get("FAKE_PRIMARY") else None)}}
pace = os.environ.get("FAKE_PACE", "none")
if pace == "expected":
    entry["pace"] = {"secondary": {"expectedUsedPercent": float(os.environ["FAKE_EXPECTED"])}}
if pace == "wontlast":
    entry["pace"] = {"secondary": {"expectedUsedPercent": elapsed, "willLastToReset": False}}
print(json.dumps([entry]))
PY
FAKE
chmod +x "$TMP/bin/codexbar"

quota() { PATH="$TMP/bin:$PATH" python3 -I "$SCRIPTS/codex-quota.py"; }
expect() { # expect <verdict> <label>
  local out; out="$(quota)"
  head -1 <<<"$out" | grep -qx "QUOTA: $1" || { echo "$out" >&2; fail "$2: wanted $1"; }
}

export FAKE_TIER=pro FAKE_USED=7  FAKE_ELAPSED=14; expect ample "pro, behind pace"
export FAKE_TIER=pro FAKE_USED=55 FAKE_ELAPSED=50; expect ample "pro, 5 points ahead, 45% left"
export FAKE_TIER=pro FAKE_USED=65 FAKE_ELAPSED=50; expect tight "pro, 15 points ahead"
export FAKE_TIER=pro FAKE_USED=65 FAKE_ELAPSED=60; expect tight "pro, 35% left mid-week"
export FAKE_TIER=pro FAKE_USED=30 FAKE_ELAPSED=10; expect tight "pro, 20 points ahead"
export FAKE_TIER=plus FAKE_USED=10 FAKE_ELAPSED=20; expect ample "plus, well behind pace"
export FAKE_TIER=plus FAKE_USED=30 FAKE_ELAPSED=20; expect tight "plus, 10 points ahead"
export FAKE_TIER=plus FAKE_USED=3 FAKE_ELAPSED=0;   expect ample "plus, tiny usage at the window start"
export FAKE_TIER=free FAKE_USED=0  FAKE_ELAPSED=50; expect tight "free never ample"
export FAKE_TIER=mystery FAKE_USED=0 FAKE_ELAPSED=50; expect unknown "unrecognised tier"
export FAKE_TIER=pro FAKE_USED=7 FAKE_ELAPSED=14 FAKE_PRIMARY=85; expect tight "short window nearly spent"
unset FAKE_PRIMARY
FAKE_USED=65 FAKE_ELAPSED=60 OPUS_CODEX_FLOW_MIN_REMAINING=30 expect ample "env override"
FAKE_USED=65 FAKE_ELAPSED=60 OPUS_CODEX_FLOW_MIN_REMAINING=oops expect unknown "bad env override"

# end of window: expiring headroom lowers the floor; mid-week with the same remaining share stays tight
export FAKE_TIER=pro
FAKE_USED=75 FAKE_ELAPSED=92 expect ample "end of window, 25% left and 17 points behind pace"
FAKE_USED=88 FAKE_ELAPSED=92 expect tight "end of window, only 12% left"
FAKE_USED=86 FAKE_ELAPSED=92 expect tight "end of window, only 6 points behind pace: floor not lowered"
FAKE_USED=60 FAKE_ELAPSED=60 expect ample "mid-week, on pace, 40% left"
FAKE_USED=62 FAKE_ELAPSED=70 expect tight "30% of the window left, not yet the last quarter"
out="$(FAKE_USED=75 FAKE_ELAPSED=92 quota)"; grep -q 'floor lowered' <<<"$out" || fail "end-of-window note missing"

# CodexBar pace is preferred, and willLastToReset=false forces tight
FAKE_USED=20 FAKE_ELAPSED=50 FAKE_PACE=expected FAKE_EXPECTED=5  expect tight "codexbar pace says 15 points ahead"
FAKE_USED=20 FAKE_ELAPSED=5  FAKE_PACE=expected FAKE_EXPECTED=40 expect ample "codexbar pace says well behind"
FAKE_USED=20 FAKE_ELAPSED=50 FAKE_PACE=wontlast expect tight "codexbar projects it will not last"

# odd data gives unknown, never a traceback
for mode in garbage dict nowindow stale; do
  out="$(FAKE_MODE=$mode FAKE_USED=7 FAKE_ELAPSED=14 quota 2>&1)" || fail "$mode: nonzero exit"
  head -1 <<<"$out" | grep -qx 'QUOTA: unknown' || { echo "$out" >&2; fail "$mode: wanted unknown"; }
  ! grep -q Traceback <<<"$out" || fail "$mode: traceback"
done
out="$(PATH="/usr/bin:/bin" python3 -I "$SCRIPTS/codex-quota.py")"
head -1 <<<"$out" | grep -qx 'QUOTA: unknown' || fail "missing codexbar not unknown"

# agent definition and block
AGENT="$ROOT/agents/digest.md"
for want in '^name: digest$' '^model: haiku$' '^effort: low$' '^tools: .*Read'; do
  grep -Eq "$want" "$AGENT" || fail "digest agent lacks $want"
done
! grep -Eq '^tools: .*(Write|Edit)' "$AGENT" || fail "digest agent has edit tools"
grep -q 'QUOTA: ample' "$ROOT/skills/opus-codex-flow/claude-md-block.md" || fail "block does not tie Codex to the quota check"

# sync-claude-md.py (CLAUDE_CONFIG_DIR points at a temp dir)
export CLAUDE_CONFIG_DIR="$TMP/cfg"; MD="$CLAUDE_CONFIG_DIR/CLAUDE.md"
mkdir -p "$CLAUDE_CONFIG_DIR"
sync() { python3 -I "$SCRIPTS/sync-claude-md.py" "$@"; }
count() { grep -c "$1" "$2" || true; }

out="$(sync)"; grep -q '"systemMessage"' <<<"$out" || fail "no user-visible message on first write"
[ "$(count 'opus-codex-flow:begin' "$MD")" -eq 1 ] || fail "block not created in a new file"
out="$(sync)"; [ -z "$out" ] || fail "second sync should be silent: $out"

printf '# Mine\n\nkeep this\n' > "$TMP/real.md"; rm "$MD"; ln -s "$TMP/real.md" "$MD"; rm -rf "$CLAUDE_CONFIG_DIR/opus-codex-flow"
sync >/dev/null
[ -L "$MD" ]                                                   || fail "symlink replaced"
[ "$(count 'opus-codex-flow:begin' "$TMP/real.md")" -eq 1 ]    || fail "block not added through symlink"
head -3 "$TMP/real.md" | grep -q 'keep this'                   || fail "user text disturbed"
cmp -s "$TMP/real.md.opus-codex-flow.bak" <(printf '# Mine\n\nkeep this\n') || fail "backup wrong"
cp "$TMP/real.md" "$TMP/after-first"; sync >/dev/null
cmp -s "$TMP/real.md" "$TMP/after-first"                        || fail "second sync changed the file"

python3 -I - "$TMP/real.md" <<'PY'
import sys; p = sys.argv[1]; t = open(p).read()
open(p, "w").write(t.replace("Applies only while", "STALE TEXT while"))
PY
sync >/dev/null
! grep -q 'STALE TEXT' "$TMP/real.md"                          || fail "stale block not refreshed"
[ "$(count 'opus-codex-flow:begin' "$TMP/real.md")" -eq 1 ]    || fail "block duplicated on refresh"

# removal sticks: remove, then sync must not bring it back; add does
sync remove >/dev/null
! grep -q 'opus-codex-flow' "$TMP/real.md"                     || fail "remove left the block"
cmp -s "$TMP/real.md" <(printf '# Mine\n\nkeep this\n')         || { cat "$TMP/real.md" >&2; fail "remove did not restore the file"; }
sync >/dev/null; ! grep -q 'opus-codex-flow' "$TMP/real.md"    || fail "sync re-added a removed block"
sync add >/dev/null; [ "$(count 'opus-codex-flow:begin' "$TMP/real.md")" -eq 1 ] || fail "add did not add"
python3 -I - "$TMP/real.md" <<'PY'
import re, sys; p = sys.argv[1]; t = open(p).read()
open(p, "w").write(re.sub(r"\n?<!-- opus-codex-flow:begin.*?end -->\n", "", t, flags=re.S))
PY
sync >/dev/null; ! grep -q 'opus-codex-flow' "$TMP/real.md"    || fail "block deleted by hand came back"
sync remove >/dev/null

# opt-out
rm -rf "$CLAUDE_CONFIG_DIR/opus-codex-flow"; OPUS_CODEX_FLOW_NO_CLAUDE_MD=1 sync >/dev/null
! grep -q 'opus-codex-flow' "$TMP/real.md"                     || fail "opt-out ignored by sync"

# malformed markers: never touch the user's text
rm -rf "$CLAUDE_CONFIG_DIR/opus-codex-flow"; rm "$MD"
# shellcheck disable=SC2016  # backticks are literal text in these fixtures
for bad in 'begin-only' 'quoted-inline' 'two-begins' 'end-first'; do
  case $bad in
    begin-only)    printf 'A\n<!-- opus-codex-flow:begin (x) -->\nkeep 1\nkeep 2\n' ;;
    quoted-inline) printf 'A `<!-- opus-codex-flow:begin -->` quoted\nkeep 1\nkeep 2\n' ;;
    two-begins)    printf 'A\n<!-- opus-codex-flow:begin -->\nkeep 1\n<!-- opus-codex-flow:begin -->\nkeep 2\n<!-- opus-codex-flow:end -->\n' ;;
    end-first)     printf '<!-- opus-codex-flow:end -->\nkeep 1\n<!-- opus-codex-flow:begin -->\nkeep 2\n' ;;
  esac > "$MD"
  cp "$MD" "$TMP/before"
  out="$(sync)"; sync >/dev/null; sync remove >/dev/null || true
  cmp -s "$MD" "$TMP/before" || { cat "$MD" >&2; fail "$bad: user text changed"; }
done
# a quoted marker with other text on its line is not a marker, so the block is simply added
# shellcheck disable=SC2016
printf 'A `<!-- opus-codex-flow:begin -->` quoted\nkeep 1\n' > "$MD"; rm -rf "$CLAUDE_CONFIG_DIR/opus-codex-flow"
sync >/dev/null; sync >/dev/null
grep -q 'keep 1' "$MD"                                         || fail "inline-quoted marker lost user text"
grep -q 'quoted' "$MD"                                         || fail "inline-quoted marker lost user text"
[ "$(count '^<!-- opus-codex-flow:begin' "$MD")" -eq 1 ]       || fail "inline-quoted case: block count"

# CRLF is preserved
rm -rf "$CLAUDE_CONFIG_DIR/opus-codex-flow"; printf 'one\r\ntwo\r\n' > "$MD"
sync >/dev/null
[ "$(python3 -I -c "import sys;t=open(sys.argv[1],newline='').read();print(t.count('\n')-t.count('\r\n'))" "$MD")" -eq 0 ] || fail "CRLF file got bare LF"
sync remove >/dev/null
cmp -s "$MD" <(printf 'one\r\ntwo\r\n')                         || fail "CRLF file not restored by remove"

# missing config dir: do nothing, create nothing
rm -rf "$TMP/nocfg"; CLAUDE_CONFIG_DIR="$TMP/nocfg" sync >/dev/null
[ ! -e "$TMP/nocfg" ]                                          || fail "created a config dir"
echo 'policy ok'
