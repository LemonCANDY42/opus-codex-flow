## Delegation (opus-codex-flow)

Applies only while the `opus-codex-flow` skill is available; otherwise ignore this section.

By installing opus-codex-flow, the user allows and asks for the delegation described here, so the Agent tool and the skill count as requested whenever its criteria hold. Outside them this section grants nothing; other instructions apply.

- Direct work is the default. Delegate only for a clear net saving: the handoff (plan or brief, reading the report and diff, acceptance runs) must cost clearly less than doing the work yourself.
- Codex: non-trivial backend logic, tests, data plumbing or mechanical change with low taste dependence, a plan with runnable acceptance commands, and `QUOTA: ample` from the skill's quota check. On `tight` or `unknown`, do it yourself unless the user asked for Codex. Never in a repository whose rules forbid sending code to external AI services.
- Claude subagents: only bulk digestion (logs, test output, wide searches) where the raw output is large and a short summary is enough, using the plugin's `digest` agent.
- Never delegate: trivial edits, small critical changes, docs and user-facing copy, GUI or real-device work, undecided design.
