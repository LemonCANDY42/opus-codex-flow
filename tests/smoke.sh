#!/usr/bin/env bash
# Smoke test for codex-slice.sh using a fake `codex` binary (no network, no tokens).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$ROOT/skills/opus-codex-flow/scripts/codex-slice.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/repo/src" "$TMP/repo/.claude/handoff/t"
cat > "$TMP/bin/codex" <<'FAKE'
#!/usr/bin/env bash
# Fake codex: records args, edits one in-scope and one out-of-scope file, writes the report.
out=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift 2;; *) echo "$1" >> "$FAKE_ARGS"; shift;; esac; done
cat > "$FAKE_STDIN"
echo "changed" > src/a.txt
echo "stray" > stray.txt
printf 'STATUS: done\nCHANGED: src/a.txt: demo\nCHECKS: none -> pass\nDEVIATIONS: none\nQUESTIONS/BLOCKERS: none\nNOTICED-BUT-UNTOUCHED: none\n' > "$out"
FAKE
chmod +x "$TMP/bin/codex"

cd "$TMP/repo"
git init -q; git config user.email t@t; git config user.name t
echo base > src/a.txt; git add -A; git commit -qm init
echo "# PLAN: t" > .claude/handoff/t/PLAN.md
mkdir -p .claude; echo "PROJECT-RULE-MARKER" > .claude/taste.md

export FAKE_ARGS="$TMP/args" FAKE_STDIN="$TMP/stdin" PATH="$TMP/bin:$PATH"
OUT="$("$RUNNER" .claude/handoff/t S1 --scope 'src/*' --model m-test --effort low)"

fail() { echo "FAIL: $1"; echo "$OUT"; exit 1; }
grep -q "STATUS: done" <<<"$OUT"                 || fail "report not printed"
grep -q "OUT OF SCOPE" <<<"$OUT"                 || fail "scope violation not flagged"
grep -q "stray.txt" <<<"$OUT"                    || fail "stray file not listed"
grep -q "m-test" "$TMP/args"                     || fail "--model not forwarded"
grep -q 'model_reasoning_effort="low"' "$TMP/args" || fail "--effort not forwarded"
grep -q "workspace-write" "$TMP/args"            || fail "sandbox not workspace-write"
grep -q "Taste Charter" "$TMP/stdin"             || fail "charter not injected"
grep -q "PROJECT-RULE-MARKER" "$TMP/stdin"       || fail "project taste not injected"
grep -q "Implement ONLY slice S1" "$TMP/stdin"   || fail "assignment missing"
[ -f .claude/handoff/t/base.sha ]                || fail "base.sha missing"

echo "fix" > "$TMP/fb.md"
"$RUNNER" .claude/handoff/t S1 --feedback "$TMP/fb.md" >/dev/null
grep -q "REVIEW FEEDBACK" "$TMP/stdin"           || fail "feedback not injected"
[ -f .claude/handoff/t/reports/S1.run2.md ]      || fail "run2 report missing"
echo "smoke ok"
