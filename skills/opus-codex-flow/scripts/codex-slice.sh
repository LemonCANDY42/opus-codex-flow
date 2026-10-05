#!/usr/bin/env bash
# Run ONE plan slice through Codex and print a compact result for the Opus planner.
#
# usage: codex-slice.sh <handoff-dir> <slice-id> --model M --effort E [--mode implement|scout|review]
#                       [--scope "glob,glob"] [--feedback FILE] [--max-lines N] [--fresh] [--repo DIR]
#
# Reports are written to <handoff-dir>/reports/. implement and review require PLAN.md (review also
# the base.sha an implement run recorded); scout requires <slice-id>.md. scout and review are read-only.
# --model and --effort are required and come from the slice's PLAN; "--effort default" keeps
# the model's own default. Default mode is implement; approvals are never requested.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL=""; EFFORT=""
SCOPE=""; FEEDBACK=""; REPO=""; MODE=implement; MAX_LINES=""; FRESH=0

[ $# -ge 2 ] || { sed -n '2,10p' "$0"; exit 2; }
HANDOFF="$1"; SLICE="$2"; shift 2
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --feedback) FEEDBACK="$2"; shift 2 ;;
    --max-lines) MAX_LINES="$2"; shift 2 ;;
    --fresh) FRESH=1; shift ;;
    --model) MODEL="$2"; shift 2 ;;
    --effort) EFFORT="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done
case "$MODE" in implement|scout|review) ;; *) echo "unknown mode: $MODE" >&2; exit 2 ;; esac
if [ -z "$MODEL" ] || [ -z "$EFFORT" ]; then
  echo "--model and --effort are required; take them from the slice's PLAN" >&2; exit 2
fi
if [ -n "$MAX_LINES" ] && [[ ! "$MAX_LINES" =~ ^[0-9]+$ ]]; then
  echo "--max-lines requires a non-negative integer" >&2; exit 2
fi

command -v codex >/dev/null || { echo "codex CLI not found" >&2; exit 3; }
HANDOFF="$(cd "$HANDOFF" && pwd)"
if [ "$MODE" = scout ]; then INPUT="$HANDOFF/$SLICE.md"; else INPUT="$HANDOFF/PLAN.md"; fi
[ -f "$INPUT" ] || { echo "missing $INPUT" >&2; exit 3; }
if [ "$MODE" = review ] && [ ! -f "$HANDOFF/base.sha" ]; then
  echo "missing $HANDOFF/base.sha; review needs the base an implement run recorded" >&2; exit 3
fi
REPO="${REPO:-$(git -C "$HANDOFF" rev-parse --show-toplevel 2>/dev/null)}"
[ -n "$REPO" ] || { echo "not inside a git repo; pass --repo" >&2; exit 3; }
cd "$REPO"

mkdir -p "$HANDOFF/reports"
if [ "$MODE" = implement ] && [ ! -f "$HANDOFF/base.sha" ]; then
  git rev-parse HEAD > "$HANDOFF/base.sha"
fi
N=1
while [ -e "$HANDOFF/reports/$SLICE.run$N.md" ] || [ -e "$HANDOFF/reports/$SLICE.run$N.log" ]; do N=$((N+1)); done
REPORT="$HANDOFF/reports/$SLICE.run$N.md"
PROMPT="$HANDOFF/reports/$SLICE.run$N.prompt.md"
LOG="$HANDOFF/reports/$SLICE.run$N.log"
THREAD="$HANDOFF/reports/$SLICE.thread"
RESUME=0
if [ "$MODE" = implement ] && [ -n "$FEEDBACK" ] && [ -f "$THREAD" ] && [ "$FRESH" -eq 0 ]; then
  RESUME=1
fi

{
  if [ "$MODE" = scout ]; then
    cat "$SKILL_DIR/scout-charter.md"
    printf '\n---\n'
    cat "$INPUT"
  elif [ "$MODE" = review ]; then
    cat "$SKILL_DIR/review-charter.md"
    printf '\n---\n# PLAN\n\n'
    cat "$INPUT"
    BASE="$(cat "$HANDOFF/base.sha")"
    printf '\n---\n# YOUR ASSIGNMENT\n\nReview everything changed since commit %s: run git diff %s -- . ":!.claude/handoff" ' "$BASE" "$BASE"
    printf 'and include untracked files listed by git status --short.\n'
  elif [ "$RESUME" -eq 1 ]; then
    cat "$FEEDBACK"
    printf '\nFix round for slice %s; working tree already has your earlier work; run the acceptance commands; end with the report.\n' "$SLICE"
  else
    cat "$SKILL_DIR/taste-charter.md"
    if [ -f "$REPO/.claude/taste.md" ]; then
      printf '\n---\n# Project taste rules (%s)\n\n' "$REPO/.claude/taste.md"
      cat "$REPO/.claude/taste.md"
    fi
    printf '\n---\n# PLAN (authoritative; decisions are final)\n\n'
    cat "$INPUT"
    if [ -n "$FEEDBACK" ]; then
      printf '\n---\n# REVIEW FEEDBACK to address (this is a fix round; the working tree already contains your earlier work)\n\n'
      cat "$FEEDBACK"
    fi
    printf '\n---\n# YOUR ASSIGNMENT\n\nImplement ONLY slice %s. Do not start other slices. ' "$SLICE"
    printf 'Run that slice'"'"'s acceptance commands before finishing. '
    printf 'Do not commit, push, or touch git history. End with the final report format from the charter.\n'
  fi
} > "$PROMPT"

ARGS=(exec --color never)
if [ "$RESUME" -eq 1 ]; then
  # Color belongs to exec; resume has no --color, -s or -C flag.
  ARGS+=(resume "$(cat "$THREAD")")
fi
ARGS+=(-m "$MODEL" -c 'approval_policy="never"' --json --disable hooks -o "$REPORT")
if [ "$EFFORT" != default ]; then ARGS+=(-c "model_reasoning_effort=\"$EFFORT\""); fi
if [ "$MODE" = implement ]; then
  ARGS+=(--output-schema "$SKILL_DIR/report.schema.json")
  if [ "$RESUME" -eq 0 ]; then
    ARGS+=(-s workspace-write -C "$REPO")
  else
    ARGS+=(-c 'sandbox_mode="workspace-write"')
  fi
  TMP="$(mktemp -d)"
  trap 'rm -rf "$TMP"' EXIT
  # Tracked files remain part of the snapshot even when .gitignore matches them.
  cp "$(git rev-parse --git-path index)" "$TMP/index"
  GIT_INDEX_FILE="$TMP/index" git add -A .
  PRE="$(GIT_INDEX_FILE="$TMP/index" git write-tree)"
else
  ARGS+=(-s read-only -C "$REPO")
fi

if [ "$MODE" = implement ]; then
  echo "[codex-slice] model=$MODEL effort=$EFFORT slice=$SLICE run=$N resume=$RESUME repo=$REPO"
fi
set +e
codex "${ARGS[@]}" - < "$PROMPT" > "$LOG" 2> "$LOG.err"
RC=$?
set -e
if [ "$RC" -ne 0 ] || [ ! -s "$REPORT" ]; then
  echo "[codex-slice] codex exit=$RC; stderr tail ($LOG.err):" >&2
  tail -n 10 "$LOG.err" >&2
fi
if [ "$MODE" != implement ]; then
  if [ -f "$REPORT" ]; then cat "$REPORT"; fi
  exit "$RC"
fi
cp "$(git rev-parse --git-path index)" "$TMP/index"
GIT_INDEX_FILE="$TMP/index" git add -A .
POST="$(GIT_INDEX_FILE="$TMP/index" git write-tree)"
THREAD_ID="$(grep -o '"thread_id"[[:space:]]*:[[:space:]]*"[^"]*"' "$LOG" | head -n 1 | sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/' || true)"
if [ -n "$THREAD_ID" ]; then printf '%s\n' "$THREAD_ID" > "$THREAD"; fi

echo; echo "=== CODEX REPORT ==="
if [ -s "$REPORT" ]; then cat "$REPORT"; else echo "(empty; see $LOG)"; fi

echo; echo "=== THIS RUN ==="
git diff --stat "$PRE" "$POST" -- . ':!.claude/handoff' | tail -n 40
ADDED=0; DELETED=0
while read -r added deleted _; do
  if [ "$added" != '-' ]; then ADDED=$((ADDED+added)); DELETED=$((DELETED+deleted)); fi
done < <(git diff --numstat "$PRE" "$POST" -- . ':!.claude/handoff')
printf 'CHANGE SIZE: +%s -%s' "$ADDED" "$DELETED"
if [ -n "$MAX_LINES" ]; then
  BUDGET=within
  if [ $((ADDED+DELETED)) -gt "$MAX_LINES" ]; then BUDGET=OVER; fi
  printf ' (budget %s: %s)' "$MAX_LINES" "$BUDGET"
fi
printf '\n'

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
    [ "$ok" -eq 1 ] || OUT="$OUT  $f"$'\n'
  done < <(git diff --name-only "$PRE" "$POST" -- . ':!.claude/handoff')
  echo; echo "=== SCOPE CHECK (${SCOPE}) ==="
  if [ -n "$OUT" ]; then echo "OUT OF SCOPE:"; printf '%s' "$OUT"; else echo "all changed files in scope"; fi
fi

echo; echo "=== USAGE ==="
USAGE="$(grep -o '"usage"[[:space:]]*:[[:space:]]*{[^}]*}' "$LOG" | tail -n 1 | sed 's/^[^{]*//' || true)"
echo "${USAGE:-unavailable}"
exit "$RC"
