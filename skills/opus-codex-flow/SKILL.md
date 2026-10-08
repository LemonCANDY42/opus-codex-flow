---
name: opus-codex-flow
description: Decides whether and to whom to delegate coding work, conservatively, and runs the delegation. Opus plans and reviews; Codex implements or scouts when its quota is clearly ample; a cheap Claude subagent (Haiku digest) handles bulk read-only digestion. Use only when the handoff clearly costs less than doing the work directly. The user can also invoke it with /opus-codex-flow <requirement>. Not for trivial edits, small critical changes, docs or user-facing copy, GUI work, or undecided design.
argument-hint: <requirement>
---

# Opus plans → Codex implements → Opus reviews

You are the planner and reviewer. Codex does the bulk of the typing. Your tokens go to
decisions, taste, and verification, not to writing code or reading whole files.

Files in this skill: `taste-charter.md` (implement rules), `scout-charter.md` (read-only
investigation rules), `review-charter.md` (independent review rules), `report.schema.json`, `plan-template.md`,
`scripts/codex-slice.sh` (the delegation runner), `scripts/codex-quota.py` (quota gate),
`scripts/sync-claude-md.py` with `claude-md-block.md` (the managed block in the global CLAUDE.md),
and the plugin's `digest` agent (Haiku, no edit tools).

Runner path: `${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh`. If that variable is not expanded
in your session, locate the script with
`find ~/.claude -path '*opus-codex-flow/scripts/codex-slice.sh' | head -1` and use that path.

Requirement: $ARGUMENTS (empty when you invoked this skill yourself: the requirement is the task at hand)

If the requirement is exactly `uninstall`: run `python3 "${CLAUDE_SKILL_DIR}/scripts/sync-claude-md.py" remove`,
report what it printed, tell the user to run `/plugin uninstall opus-codex-flow@opus-codex-flow`, and stop.

## 0. Gate (direct work is the default)

Delegate only when every check passes. Otherwise do the work yourself and say so in one line.

1. Net cost. The handoff costs you a plan or brief, a read of the report and diff, and the
   acceptance runs. Delegate only when that is clearly less than doing the work directly
   (reading, writing, debug loops). These are rules of thumb; calibrate them against the
   observations table in the routing file.
   - Codex slice: roughly 150 or more changed lines over 3 or more files, or 3 or more
     build-and-test cycles, or 10 or more files of reading you do not need verbatim; and the
     plan fits in about 50 lines; and acceptance is runnable commands. Reading this skill and
     the routing file is part of the overhead: read only the routing file's choices and quota
     sections, not its observations table.
   - Claude subagent: the raw output you would otherwise read is large (about 10 or more
     files, long logs, full test output) and a summary of about 300 words is enough.
   - If settling the plan takes more effort than half the work, do it directly.
2. Eligible work. Leans on backend logic, tests, data plumbing or mechanical change rather
   than taste, and can be fixed in a plan with runnable acceptance. Keep with Claude:
   trivial edits, small critical changes, docs and user-facing copy, GUI or real-device work,
   and undecided design (decide first, then delegate). Rows in the user's routing file that
   say otherwise win.
3. Quota. Once per task, run `python3 "${CLAUDE_SKILL_DIR}/scripts/codex-quota.py"` (it reads
   CodexBar, a few seconds). It prints `QUOTA: ample|tight|unknown`, judged from the
   subscription tier, the weekly window's remaining share and CodexBar's pace. Late in the
   window, unspent headroom well ahead of pace lowers the remaining-share floor.
   Codex work needs `ample`. On `tight` or `unknown`, do it yourself unless the user invoked
   the skill or asked for Codex; then go on and state the verdict in one line.
4. Executor.

   | Work | Executor |
   |---|---|
   | Broad read-only investigation, Codex ample | Codex scout (little Claude quota: you write the question and read the report) |
   | Backend logic, tests, mechanical change with a plan | Codex implement slice |
   | Bulk digestion that stays local: logs, test output, search sweeps | Claude subagent `opus-codex-flow:digest` (Haiku, low effort) |
      | Independent review of a PR | per the routing file |
   | Anything else | directly |

5. Needs a git repo and the `codex` CLI for Codex work. Otherwise say what is missing.
6. Non-trivial Codex work: prefer an isolated worktree (`EnterWorktree`) so the diff against
   the base is exactly this task.
7. Ask the user only when a missing answer would change behavior, an interface, or
   compatibility and cannot be inferred. Otherwise decide, record it in PLAN.md, move on.

Stop-loss: two failed fix rounds, a plan that keeps growing, or a slice well over its change
budget means the handoff is losing. Take over and do it directly.

## 1. Plan (your main job)

1. Investigate the minimum needed. Use the repo's owning docs and existing patterns.
   Broad reading follows the executor table in section 0.
2. Write `.claude/handoff/<slug>/PLAN.md` from `plan-template.md`. Rules:
   - Resolve every behavior, interface, compatibility, and state-ownership decision NOW.
     The main failure of this workflow is a decision left implicit, which Codex then
     fills in with its own taste.
   - Slices are small, ordered, each with a path scope, wiring points, and acceptance
     as runnable commands. "Looks right" is not acceptance.
   - Put task-specific taste in the plan ("reuse X", "no new dependency", "match style
     of Y"). Cross-task taste lives in `taste-charter.md`; repo-specific taste may live
     in `<repo>/.claude/taste.md` and is injected automatically.
3. Self-check before delegating: each slice has scope + commands + wiring; no decision
   is deferred with "as appropriate". Fix the plan, not the code.
4. Tell the user the plan in ≤10 lines (Chinese) and continue without waiting, unless
   the plan involves irreversible/external actions or unresolved ambiguity.

## 2. Delegate (one slice at a time)

```bash
"${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh" .claude/handoff/<slug> S1 \
  --model gpt-6.1-sol --effort high --scope 'src/foo/*,tests/foo/*' --max-lines 100
```

- Run with `run_in_background: true` and wait for the completion notice. Do not poll.
- `--model` and `--effort` are required. Take them from the slice's line in PLAN.md
  (see "Model and effort" below); the script never chooses for you.
- Implement mode (the default) prints the schema-constrained JSON report, this run's
  diff stat and added/deleted line count, a scope check when requested, and token usage.
  `--max-lines N` marks added + deleted lines over N as `OVER`; budget and scope warnings
  do not change Codex's exit code. Do not re-read files Codex touched in full.
- Slices run sequentially by default. Parallel only when scopes are disjoint and each
  uses its own worktree.
- JSON `status: "blocked"` or non-empty `questions`: answer by amending PLAN.md (decisions
  section), then re-run the slice. Do not patch around a planning gap in code.

For a read-only investigation, write the question, required report format, and length
in `.claude/handoff/<slug>/Q1.md`, then run:

```bash
"${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh" .claude/handoff/<slug> Q1 --mode scout \
  --model gpt-6.1-sol --effort medium
```

Scout requires no PLAN.md, uses `read-only`, and prints only the report. It does not
apply the JSON schema, scope check, or change accounting; builds/tests require an
explicit request in the question file. Claims need `path:line` evidence.

## Claude subagents (conservative)

Only for bulk digestion, the row in section 0. They share your usage limits and start with no
conversation history, so a vague brief wastes the spend. The dependable gain is context
isolation: big raw output stays out of your context and only the summary returns. Any price
gain from the Haiku model is unverified, because model routing has been unreliable
([anthropics/claude-code#43869](https://github.com/anthropics/claude-code/issues/43869))
and you cannot always see which model served a call. If you learn the parent model served it,
stop using subagents for cost reasons in that session.

- Brief = objective, what to look at, the commands allowed, and a length cap (about 300
  words, evidence as `path:line` or quoted lines). The `digest` agent has no edit tools:
  edits go to Codex or stay with you.
- One at a time by default. Two to four only for independent questions run in parallel.
  No nesting. More than four needs the user's say-so.
- Effort comes from the agent definition (`digest` is `low`).

## Model and effort (decided in the plan, never by the script)

Write `Model / effort:` on every slice in PLAN.md and pass exactly that to the runner.

The authority is the user's routing file `~/.claude/opus-codex-flow/model-routing.md`.
Read it before writing a plan. If it does not exist, create it from the default table
below, in the user's language, with the same sections: principles, current choices,
observations, change log.

Default table (models available on 2026-10-05):

| Work | Model | Effort |
|---|---|---|
| Read-only scout | `gpt-6.1-sol` | `medium`; `high` when tracing across modules |
| Implementation slice with clear boundaries | `gpt-6.1-sol` | `high` |
| Cross-layer, concurrency, lifecycle, or UI slice | `gpt-6.1-sol` | `xhigh` |
| Independent review, once per PR | `gpt-6-astra` | `high` |
| Mechanical change (rename, bulk replace) | `gpt-6-luna` | `default` |
| GUI or real-device work | Claude does it | not delegated |
| Small critical changes, docs, user-facing copy | Claude does it | not delegated |

`--effort default` leaves the model's own default in place.

You maintain the routing file on your own judgment. Quality comes first, then cost and
speed; Codex usage is prepaid, so never drop a tier only to save Codex usage. Whether to
delegate at all is the quota gate's call (section 0), not a row in this table. When
`~/.codex/models_cache.json` lists a newer model, or results on real slices contradict a
row, change the row and add a dated change-log line stating what changed and the evidence
(fix rounds, plan deviations, review findings, duration, or a checkable public evaluation).
After each real slice add one line to the observations table, including your own handoff
overhead against your estimate of doing it directly, so the section 0 thresholds can be tuned. Tell the user in your closing
report whenever you changed a row.

## 3. Verify and review

1. Run the slice's acceptance commands yourself. Deterministic checks first; they are
   cheap and tests alone do not prove the plan was followed.
2. Read `git diff <base>` (the diff, not whole files) and judge against PLAN.md and the
   charter. Check specifically:
   - every Decision honored exactly (signatures, behavior, compatibility)
   - scope respected; no unrelated edits; no new dependency
   - each charter habit: speculative abstraction, defensive padding, shims, duplicate
     helpers, narrating comments, mock-only tests, weakened tests, UI drift from tokens
   - wired up: new code is reachable from its callers/registrations
   - obsolete code removed
3. Once per PR (and earlier for a high-risk slice) run the independent review. It is
   read-only, reads PLAN.md and the diff since `base.sha`, and reports ranked findings:

   ```bash
   "${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh" .claude/handoff/<slug> R1 --mode review \
     --model gpt-6-astra --effort high
   ```

   It looks for correctness and plan violations. Taste stays your job. Verify each
   finding against the code before acting on it.
4. Verdict per slice: accept, or write numbered concrete issues (file, evidence, what to
   change) to `.claude/handoff/<slug>/feedback-S1.md` and re-run:

```bash
"${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh" .claude/handoff/<slug> S1 \
  --model gpt-6.1-sol --effort high --feedback .claude/handoff/<slug>/feedback-S1.md --scope '...'
```

- Maximum 2 fix rounds per slice. After that, either edit the few remaining lines
  yourself (if tiny) or stop and report to the user with the blocker. Do not loop.
- If the same class of issue repeats, the plan or charter is missing a rule. Add it to
  PLAN.md or the repo's `.claude/taste.md`, then re-run.
- Fix rounds resume the saved `reports/<slice>.thread` by default with only feedback
  and a short assignment. `--fresh`, or a missing thread file, sends the full prompt
  plus feedback in a cold run.

## 4. Close

- After the last slice: run the full acceptance set once, confirm base..HEAD diff has
  no stray files (handoff dir is not part of the change; add `.claude/handoff/` to
  `.gitignore` if the repo does not already ignore it).
- Report to the user in Chinese: what changed, evidence (commands + results), plan
  deviations, anything Codex noticed but left untouched, what remains unverified, and one
  line on handoff overhead against your estimate of doing it directly.
- Commit, push, or open a PR only when the user asked or the project rules require it.

## Token discipline (why this saves Claude spend)

- Plan once, precisely; Codex does the long edits and test iteration.
- Read reports and diffs, not whole files. Don't narrate between steps.
- No polling, no re-planning after a fix round unless the plan was wrong.
- Use deterministic commands as the first review gate; spend Opus judgment on the diff.

## Known limits

- Taste is enforced by the charter and your review, not by Codex's sandbox. Codex can
  still violate a rule; your review is the control.
- `workspace-write` sandbox has no network. Slices needing installs or network need the
  user's explicit go-ahead to relax it.
- Codex can lose cross-module wiring on long runs; keep slices small and check wiring.
