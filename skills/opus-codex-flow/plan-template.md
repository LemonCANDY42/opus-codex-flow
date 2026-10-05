# PLAN: <short title>

Slug: <slug> · Date: <YYYY-MM-DD> · Base: <branch@sha>

## Intent
<2-4 lines: what outcome the user wants and why. No solution detail here.>

## Decisions (already made; the implementer must not revisit)
- <Behavior decision>: <chosen option>. <one-line reason>
- <Interface/contract decision>: <exact signature / schema / endpoint / event>
- <Compatibility decision>: <what must keep working / what may break>
- <Data/state ownership decision>: <who owns what, lifecycle if relevant>

## Taste constraints specific to this task
<Only the delta beyond taste-charter.md. Examples: "reuse `FooListView`, do not add a new
list component"; "no new dependency"; "match error style in services/billing.py".>

## Non-goals
- <explicitly out of scope>

## Slices
Run in order unless marked parallel. Each slice is independently checkable.

### S1 — <name>
- Scope (paths the slice may touch): `<glob>`, `<glob>`
- Do: <concrete work, referencing existing files/patterns to follow>
- Wiring: <where it must be connected: callers, registration, routes, exports>
- Model / effort: <from the table in SKILL.md, e.g. gpt-6.1-sol / high>
- Expected size: <approximate added + deleted lines for this slice>
- Acceptance (commands that decide pass/fail; no self-grading):
  - `<command>` -> <expected result>
  - Behavior: <observable behavior covered by a command or a named test>

### S2 — <name>
- Model / effort: <from the table in SKILL.md, e.g. gpt-6.1-sol / high>
- Expected size: <approximate added + deleted lines for this slice>
...

## Review focus (for the Opus review pass)
- <the 2-3 places where a faithful-looking implementation is most likely wrong>
