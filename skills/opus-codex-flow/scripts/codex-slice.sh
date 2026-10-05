#!/usr/bin/env bash
# Run ONE plan slice through Codex and print a compact result for the Opus planner.
#
# usage: codex-slice.sh <handoff-dir> <slice-id> [--scope "glob,glob"] [--feedback FILE]
#                       [--model M] [--effort E] [--repo DIR]
#
# <handoff-dir> contains PLAN.md; reports are written to <handoff-dir>/reports/.
# Defaults: model gpt-6.1-sol, effort high, sandbox workspace-write, approvals never.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL="${CODEX_SLICE_MODEL:-gpt-6.1-sol}"
EFFORT="${CODEX_SLICE_EFFORT:-high}"
SCOPE=""; FEEDBACK=""; REPO=""

[ $# -ge 2 ] || { sed -n '2,8p' "$0"; exit 2; }
HANDOFF="$1"; SLICE="$2"; shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --scope) SCOPE="$2"; shift 2 ;;
    --feedback) FEEDBACK="$2"; shift 2 ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

command -v codex >/dev/null || { echo "codex CLI not found" >&2; exit 3; }
HANDOFF="$(cd "$HANDOFF" && pwd)"
[ -f "$HANDOFF/PLAN.md" ] || { echo "missing $HANDOFF/PLAN.md" >&2; exit 3; }
REPO="${REPO:-$(git -C "$HANDOFF" rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] || { echo "not inside a git repo; pass --repo" >&2; exit 3; }
cd "$REPO"

mkdir -p "$HANDOFF/reports"
[ -f "$HANDOFF/base.sha" ] || git rev-parse HEAD > "$HANDOFF/base.sha"
BASE="$(cat "$HANDOFF/base.sha")"

N=1
while [ -e "$HANDOFF/reports/$SLICE.run$N.md" ]; do N=$((N+1)); done
REPORT="$HANDOFF/reports/$SLICE.run$N.md"
PROMPT="$HANDOFF/reports/$SLICE.run$N.prompt.md"

{
  cat "$SKILL_DIR/taste-charter.md"
  if [ -f "$REPO/.claude/taste.md" ]; then
    printf '\n---\n# Project taste rules (%s)\n\n' "$REPO/.claude/taste.md"
    cat "$REPO/.claude/taste.md"
  fi
  printf '\n---\n# PLAN (authoritative; decisions are final)\n\n'
  cat "$HANDOFF/PLAN.md"
  if [ -n "$FEEDBACK" ]; then
    printf '\n---\n# REVIEW FEEDBACK to address (this is a fix round; the working tree already contains your earlier work)\n\n'
    cat "$FEEDBACK"
  fi
  printf '\n---\n# YOUR ASSIGNMENT\n\nImplement ONLY slice %s. Do not start other slices. ' "$SLICE"
  printf 'Run that slice'"'"'s acceptance commands before finishing. '
  printf 'Do not commit, push, or touch git history. End with the final report format from the charter.\n'
} > "$PROMPT"

echo "[codex-slice] model=$MODEL effort=$EFFORT slice=$SLICE run=$N repo=$REPO"
set +e
codex exec \
  -m "$MODEL" \
  -c "model_reasoning_effort=\"$EFFORT\"" \
  -c 'approval_policy="never"' \
  -s workspace-write \
  -C "$REPO" \
  --color never \
  -o "$REPORT" \
  - < "$PROMPT" > "$HANDOFF/reports/$SLICE.run$N.log" 2>&1
RC=$?
set -e
echo "[codex-slice] codex exit=$RC  log=$HANDOFF/reports/$SLICE.run$N.log"

echo; echo "=== CODEX REPORT ($REPORT) ==="
if [ -s "$REPORT" ]; then cat "$REPORT"; else echo "(empty; see log tail below)"; tail -n 20 "$HANDOFF/reports/$SLICE.run$N.log"; fi

echo; echo "=== CHANGES vs base ${BASE:0:10} ==="
git add -N . 2>/dev/null || true
git diff --stat "$BASE" -- . ':!.claude/handoff' | tail -n 40

if [ -n "$SCOPE" ]; then
  OUT=""
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    ok=0
    IFS=',' read -ra PATS <<< "$SCOPE"
    for p in "${PATS[@]}"; do
      # shellcheck disable=SC2254
      case "$f" in $p) ok=1; break ;; esac
    done
    [ $ok -eq 1 ] || OUT="$OUT  $f"$'\n'
  done < <(git diff --name-only "$BASE" -- . ':!.claude/handoff')
  echo; echo "=== SCOPE CHECK (${SCOPE}) ==="
  if [ -n "$OUT" ]; then echo "OUT OF SCOPE:"; printf '%s' "$OUT"; else echo "all changed files in scope"; fi
fi
exit $RC
