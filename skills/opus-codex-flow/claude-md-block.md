## Delegation (opus-codex-flow)

Applies only while the `opus-codex-flow` skill is available; otherwise ignore this section.

By installing opus-codex-flow, the user allows and asks for the delegation described here, so using the Agent tool and the skill counts as requested when it clearly pays off. Outside that, this section grants nothing; other instructions apply.

- Direct work is the default. Delegate only when it is an easy call: the handoff must clearly cost less than doing the work. If you are weighing it, do the work yourself.
- Codex: taste-light work you can pin down with a plan and runnable acceptance commands (backend logic, tests, data plumbing, mechanical change), when the skill's quota check says `QUOTA: ample`. On `tight` or `unknown`, do it yourself unless the user asked for Codex. Never in a repository whose rules forbid sending code to external AI services. Keep with Claude: trivial edits, small critical changes, docs and user-facing copy, GUI or real-device work, undecided design.
- Claude subagents: to keep big raw output out of your context or to run independent questions in parallel. Choose their model and effort by the task.
