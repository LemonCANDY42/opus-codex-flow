---
name: opus-codex-flow
description: Opus plans and reviews, Codex (gpt-6.1-sol) implements, with taste constraints injected. Invoke explicitly with /opus-codex-flow <requirement> for non-trivial feature or fix work where you want Claude spend kept low.
disable-model-invocation: true
argument-hint: <requirement>
---

# Opus plans → Codex implements → Opus reviews

You are the planner and reviewer. Codex does the bulk of the typing. Your tokens go to
decisions, taste, and verification, not to writing code or reading whole files.

Files in this skill: `taste-charter.md` (rules injected into every Codex run),
`plan-template.md`, `scripts/codex-slice.sh` (the delegation runner).

Runner path: `${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh`. If that variable is not expanded
in your session, locate the script with
`find ~/.claude -path '*opus-codex-flow/scripts/codex-slice.sh' | head -1` and use that path.

Requirement: $ARGUMENTS

## 0. Gate

- Needs a git repo and the `codex` CLI. Otherwise stop and say what is missing.
- Trivial work (≤2 files, ≤30 lines, no new logic): just do it yourself, skip Codex.
- Non-trivial work: prefer an isolated worktree (`EnterWorktree`) so the diff against
  the base is exactly this task.
- Ask the user only when a missing answer would change behavior, an interface, or
  compatibility and cannot be inferred. Otherwise decide, record it in PLAN.md, move on.

## 1. Plan (your main job)

1. Investigate the minimum needed. Use the repo's owning docs and existing patterns.
   Delegate broad reading to an `Explore`-type subagent instead of loading files yourself.
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
  --scope 'src/foo/*,tests/foo/*'
```

- Run with `run_in_background: true` and wait for the completion notice. Do not poll.
- Defaults: model `gpt-6.1-sol`, effort `high`. Use `--effort xhigh` for cross-layer,
  lifecycle-heavy, or UI work. Override the model with `--model` only on user request.
- The script prints only Codex's final report, the diff stat, and a scope check. Do not
  re-read files Codex touched in full.
- Slices run sequentially by default. Parallel only when scopes are disjoint and each
  uses its own worktree.
- `STATUS: blocked` or non-empty QUESTIONS: answer by amending PLAN.md (decisions
  section), then re-run the slice. Do not patch around a planning gap in code.

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
3. For larger or higher-risk diffs, additionally spawn the read-only `reviewer-sol`
   agent with the PLAN path and base sha, and merge its concrete findings with yours.
4. Verdict per slice: accept, or write numbered concrete issues (file, evidence, what to
   change) to `.claude/handoff/<slug>/feedback-S1.md` and re-run:

```bash
"${CLAUDE_SKILL_DIR}/scripts/codex-slice.sh" .claude/handoff/<slug> S1 \
  --feedback .claude/handoff/<slug>/feedback-S1.md --scope '...'
```

- Maximum 2 fix rounds per slice. After that, either edit the few remaining lines
  yourself (if tiny) or stop and report to the user with the blocker. Do not loop.
- If the same class of issue repeats, the plan or charter is missing a rule. Add it to
  PLAN.md or the repo's `.claude/taste.md`, then re-run.

## 4. Close

- After the last slice: run the full acceptance set once, confirm base..HEAD diff has
  no stray files (handoff dir is not part of the change; add `.claude/handoff/` to
  `.gitignore` if the repo does not already ignore it).
- Report to the user in Chinese: what changed, evidence (commands + results), plan
  deviations, anything Codex noticed but left untouched, what remains unverified.
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
