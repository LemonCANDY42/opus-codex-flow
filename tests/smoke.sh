#!/usr/bin/env bash
# Smoke test for codex-slice.sh using a fake `codex` binary (no network, no tokens).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/skills/opus-codex-flow/scripts/codex-slice.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/indexes" "$TMP/repo/src" "$TMP/repo/.claude/handoff/t"
cat > "$TMP/bin/codex" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "$FAKE_ARGS"
[ "$1" = exec ]; shift
if [ "$1" = --color ]; then [ "$2" = never ]; shift 2; fi
resume=0
if [ "$1" = resume ]; then
  resume=1; shift
  printf '%s\n' "$1" > "$FAKE_RESUME"; shift
fi
out=""; sandbox=""
while [ $# -gt 0 ]; do
  case "$1" in
    -o) out="$2"; shift 2 ;;
    -s|-C|--color)
      [ "$resume" -eq 0 ] || { echo "unsupported resume flag: $1" >&2; exit 2; }
      if [ "$1" = -s ]; then sandbox="$2"; fi
      shift 2 ;;
    -m|-c|--output-schema|--disable) shift 2 ;;
    --json|-) shift ;;
    *) echo "unexpected flag: $1" >&2; exit 2 ;;
  esac
done
cat > "$FAKE_STDIN"
case "$FAKE_EDIT" in
  first)
    echo changed > src/a.txt; echo stray > stray.txt; echo ignored > ignored.txt
    echo changed > src/tracked.txt ;;
  second) printf 'second\nslice\n' > src/b.txt ;;
  ignore) printf 'ignored.txt\nsrc/tracked.txt\nsrc/b.txt\n' > .gitignore ;;
  none) ;;
  scout) [ "$sandbox" = read-only ]; echo 'src/a.txt:1: changed' > "$out" ;;
esac
if [ "$FAKE_EDIT" != scout ]; then
  printf '{"status":"done","changed":[],"checks":[],"deviations":[],"questions":[],"noticed":[]}\n' > "$out"
fi
if [ "${FAKE_EVENTS:-1}" -eq 1 ]; then
  printf '{"type":"thread.started","thread_id":"test-thread-id"}\n'
  printf '{"type":"turn.completed","usage":{"input_tokens":12,"cached_input_tokens":8,"output_tokens":4}}\n'
fi
exit "${FAKE_RC:-0}"
FAKE
chmod +x "$TMP/bin/codex"

cd "$TMP/repo"
git init -q; git config user.email t@t; git config user.name t
echo base > src/a.txt; echo base > src/tracked.txt
printf 'ignored.txt\nsrc/tracked.txt\n' > .gitignore
git add -A; git add -f src/tracked.txt; git commit -qm init
cp .git/index "$TMP/original-index"
echo '# PLAN: t' > .claude/handoff/t/PLAN.md
echo PROJECT-RULE-MARKER > .claude/taste.md

export FAKE_ARGS="$TMP/args" FAKE_STDIN="$TMP/stdin" FAKE_RESUME="$TMP/resume"
export PATH="$TMP/bin:$PATH" TMPDIR="$TMP/indexes" FAKE_EDIT=first
OUT="$("$RUNNER" .claude/handoff/t S1 --scope 'src/*' --max-lines 1 --model m-test --effort low)"

fail() { echo "FAIL: $1"; echo "$OUT"; exit 1; }
grep -q '"status":"done"' <<<"$OUT"             || fail "report not printed"
grep -q 'OUT OF SCOPE' <<<"$OUT"                 || fail "scope violation not flagged"
grep -q 'stray.txt' <<<"$OUT"                    || fail "untracked stray file not listed"
! grep -q 'ignored.txt' <<<"$OUT"                || fail "ignored file included"
grep -q 'src/tracked.txt' <<<"$OUT"              || fail "tracked ignored file missing"
grep -q 'CHANGE SIZE: +3 -2 (budget 1: OVER)' <<<"$OUT" || fail "change budget wrong"
grep -qx 'm-test' "$FAKE_ARGS"                   || fail "--model not forwarded"
grep -qx 'model_reasoning_effort="low"' "$FAKE_ARGS" || fail "--effort not forwarded"
grep -qx workspace-write "$FAKE_ARGS"           || fail "sandbox not workspace-write"
grep -qx -- --json "$FAKE_ARGS"                 || fail "--json missing"
grep -A 1 -x -- --disable "$FAKE_ARGS" | grep -qx hooks || fail "hooks not disabled"
grep -A 1 -x -- --color "$FAKE_ARGS" | grep -qx never || fail "color not disabled"
grep -A 1 -x -- --output-schema "$FAKE_ARGS" | grep -qx "$ROOT/skills/opus-codex-flow/report.schema.json" || fail "report schema missing"
grep -q 'Taste Charter' "$FAKE_STDIN"            || fail "charter not injected"
grep -q PROJECT-RULE-MARKER "$FAKE_STDIN"        || fail "project taste not injected"
grep -q 'Implement ONLY slice S1' "$FAKE_STDIN"  || fail "assignment missing"
[ -f .claude/handoff/t/base.sha ]                || fail "base.sha missing"
[ "$(cat .claude/handoff/t/reports/S1.thread)" = test-thread-id ] || fail "thread id not saved"
grep -q '"input_tokens":12,"cached_input_tokens":8,"output_tokens":4' <<<"$OUT" || fail "usage missing"
cmp -s .git/index "$TMP/original-index"         || fail "real index altered"
git diff --cached --quiet                       || fail "content staged"
! git ls-files --error-unmatch stray.txt >/dev/null 2>&1 || fail "intent-to-add entry left"
[ -z "$(ls -A "$TMP/indexes")" ]                || fail "temporary index left behind"

export FAKE_EDIT=none
echo FIX-MARKER > "$TMP/fb.md"
OUT="$("$RUNNER" .claude/handoff/t S1 --model m-test --effort low --feedback "$TMP/fb.md")"
[ "$(cat "$FAKE_RESUME")" = test-thread-id ]      || fail "wrong resume thread"
grep -qx resume "$FAKE_ARGS"                    || fail "resume not called"
grep -qx 'sandbox_mode="workspace-write"' "$FAKE_ARGS" || fail "resume lacks write sandbox"
grep -q FIX-MARKER "$FAKE_STDIN"                || fail "feedback not injected"
! grep -Eq 'Taste Charter|# PLAN|PROJECT-RULE-MARKER' "$FAKE_STDIN" || fail "full prompt resent"
grep -q 'Fix round for slice S1' "$FAKE_STDIN"    || fail "fix assignment missing"
[ -f .claude/handoff/t/reports/S1.run2.md ]       || fail "run2 report missing"
grep -q 'CHANGE SIZE: +0 -0' <<<"$OUT"            || fail "unchanged run includes prior work"

OUT="$("$RUNNER" .claude/handoff/t S1 --model m-test --effort default --feedback "$TMP/fb.md" --fresh)"
! grep -qx resume "$FAKE_ARGS"                  || fail "--fresh resumed"
! grep -q model_reasoning_effort "$FAKE_ARGS"   || fail "--effort default still overrides effort"
grep -q 'Taste Charter' "$FAKE_STDIN"            || fail "--fresh omitted charter"
grep -q '# PLAN: t' "$FAKE_STDIN"                || fail "--fresh omitted plan"
grep -q 'REVIEW FEEDBACK' "$FAKE_STDIN"           || fail "cold feedback not injected"

export FAKE_EDIT=second
echo before > src/b.txt
OUT="$("$RUNNER" .claude/handoff/t S2 --model m-test --effort low --feedback "$TMP/fb.md" --scope 'src/b.txt' --max-lines 3)"
! grep -qx resume "$FAKE_ARGS"                  || fail "missing thread resumed"
grep -q 'Taste Charter' "$FAKE_STDIN"            || fail "missing thread omitted charter"
grep -q FIX-MARKER "$FAKE_STDIN"                || fail "missing thread omitted feedback"
grep -q 'all changed files in scope' <<<"$OUT"   || fail "earlier slice leaked into scope"
! grep -Eq 'stray.txt|src/a.txt' <<<"$OUT"         || fail "earlier slice leaked into diff"
grep -q 'CHANGE SIZE: +2 -1 (budget 3: within)' <<<"$OUT" || fail "untracked baseline or budget wrong"

mkdir -p .claude/handoff/scout
echo QUESTION-MARKER > .claude/handoff/scout/Q1.md
export FAKE_EDIT=scout
OUT="$("$RUNNER" .claude/handoff/scout Q1 --model m-test --effort low --mode scout --scope 'nothing' --max-lines 0)"
[ "$OUT" = 'src/a.txt:1: changed' ]              || fail "scout printed more than report"
grep -qx read-only "$FAKE_ARGS"                 || fail "scout not read-only"
! grep -qx -- --output-schema "$FAKE_ARGS"       || fail "scout uses schema"
grep -q 'Scout Charter' "$FAKE_STDIN"            || fail "scout charter missing"
grep -q QUESTION-MARKER "$FAKE_STDIN"            || fail "question missing"
! grep -Eq 'Taste Charter|# PLAN' "$FAKE_STDIN"   || fail "scout read implement prompt"
[ ! -e .claude/handoff/scout/base.sha ]          || fail "scout did change accounting"
[ ! -e .claude/handoff/scout/reports/Q1.thread ] || fail "scout saved implement thread"

export FAKE_EDIT=ignore
OUT="$("$RUNNER" .claude/handoff/t S3 --model m-test --effort low --scope '.gitignore,src/b.txt')"
grep -q 'CHANGE SIZE: +1 -2' <<<"$OUT"            || fail "new ignore rule not honored by post snapshot"

export FAKE_EDIT=none
OUT="$("$RUNNER" .claude/handoff/t R1 --mode review --model m-review --effort high)"
grep -qx read-only "$FAKE_ARGS"                 || fail "review not read-only"
grep -q 'Review Charter' "$FAKE_STDIN"           || fail "review charter not injected"
grep -q '# PLAN: t' "$FAKE_STDIN"                || fail "review omitted plan"
grep -q "$(cat .claude/handoff/t/base.sha)" "$FAKE_STDIN" || fail "review omitted base"
! grep -qx -- --output-schema "$FAKE_ARGS"      || fail "review used implement schema"
RC=0; "$RUNNER" .claude/handoff/scout R1 --mode review --model m --effort high >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 3 ]                                 || fail "review without PLAN/base not rejected"

export FAKE_EDIT=none FAKE_EVENTS=0 FAKE_RC=7
RC=0
OUT="$("$RUNNER" .claude/handoff/t S4 --model m-test --effort low)" || RC=$?
[ "$RC" -eq 7 ]                                || fail "codex exit code lost"
grep -qx unavailable <<<"$OUT"                  || fail "missing usage not reported"
cmp -s .git/index "$TMP/original-index"         || fail "later run altered real index"
git diff --cached --quiet                       || fail "later run staged content"
[ -z "$(ls -A "$TMP/indexes")" ]                || fail "later run left temporary index"
RC=0; "$RUNNER" .claude/handoff/t S9 --model m-test >/dev/null 2>&1 || RC=$?
[ "$RC" -eq 2 ]                                 || fail "missing --effort not rejected"
echo 'smoke ok'
