# opus-codex-flow

Plan and review with Claude Opus. Implement with Codex. Keep Claude spend low and keep your taste in the code.

A Claude Code plugin with one skill, `/opus-codex-flow`, one small agent (`digest`, Haiku, no edit tools) and a SessionStart hook. Opus writes a precise plan, a small runner hands each slice to the Codex model the plan names, and Opus reviews the diff against the plan and a taste charter. Claude can start it on its own, conservatively: only when the handoff clearly costs less than doing the work directly.

[中文说明](#中文说明)

## Why

Opus tends to make better design and taste decisions. A cheaper Codex model is good at the long typing-and-iterating part. The failure mode of splitting them is that any decision the plan leaves implicit gets filled in by the implementer's own habits. This project makes the handoff explicit:

- the plan is a file, not chat context, and resolves behavior, interface, compatibility and state-ownership decisions up front;
- each cold implement run gets a **taste charter** that names the habits to avoid (speculative abstraction, defensive padding, compatibility shims, scope creep, narrating comments, mock-only tests, unwired components);
- every slice has a path scope and acceptance **commands**, so pass/fail is not self-graded;
- Opus reads reports and diffs, not whole files, and gets a scope check for free.

## Install

Requires [Claude Code](https://claude.com/claude-code), the [Codex CLI](https://github.com/openai/codex) (`codex` on PATH, logged in), `git`, `bash` and `python3`. [CodexBar](https://github.com/steipete/CodexBar) is optional: without it the quota check says `unknown` and Claude delegates to Codex only when you ask.

```
/plugin marketplace add LemonCANDY42/opus-codex-flow
/plugin install opus-codex-flow@opus-codex-flow
```

## Use

In a git repository:

```
/opus-codex-flow add a 10% discount for orders of 10 or more units
```

You can always invoke it by hand. Claude also invokes it by itself for suitable work, see [Delegation policy](#delegation-policy).

1. **Plan.** Opus investigates, then writes `.claude/handoff/<slug>/PLAN.md` from [plan-template.md](skills/opus-codex-flow/plan-template.md). See [examples/demo/PLAN.md](examples/demo/PLAN.md).
2. **Delegate.** For each slice Opus runs `scripts/codex-slice.sh`. It builds the prompt (charter + optional `<repo>/.claude/taste.md` + plan + assignment), runs `codex exec` with `-s workspace-write` and approvals off, and prints the JSON report, this run's diff and change size, a scope check, and usage.
3. **Review.** Opus runs the acceptance commands, reviews the diff against the plan's decisions and the charter, runs `--mode review` (read-only, a stronger model) once per PR, and either accepts or writes numbered feedback.
4. **Fix.** Feedback is re-run through the same script with `--feedback`, resuming the saved thread by default. At most two rounds per slice, then Opus takes over or escalates to you.
5. **Close.** Opus reports what changed, the evidence, plan deviations, and what is unverified. It commits or opens a PR only if you ask.

Small changes are done by Opus directly; see [Delegation policy](#delegation-policy) for what is worth delegating. In the model-invoked mode, repository code can go to OpenAI through Codex without a per-task request from you, so do not enable the plugin where that is not allowed.

### Runner

```
codex-slice.sh <handoff-dir> <slice-id> --model M --effort E [--mode implement|scout|review]
               [--scope "glob,glob"] [--feedback FILE] [--max-lines N] [--fresh] [--repo DIR]
```

`--model` and `--effort` are required: the plan states them per slice and the script never picks. `--effort default` keeps the model's own default. The choices live in a user-readable file, `~/.claude/opus-codex-flow/model-routing.md`, which Claude creates from the default table in [SKILL.md](skills/opus-codex-flow/SKILL.md) and maintains with a change log: quality first, then cost and speed. `--mode review` runs a read-only independent review of the diff since the recorded base against the plan. Each run writes `reports/<slice>.runN.{md,log,prompt.md}` under the handoff directory. The model slug must exist in your Codex install; check `~/.codex/models_cache.json`.

Implement mode is the default and requires `PLAN.md`. Every invocation disables hooks and color and logs JSONL events. The final report is printed as-is and follows [report.schema.json](skills/opus-codex-flow/report.schema.json): `status`, `changed`, `checks`, `deviations`, `questions`, and `noticed`.

The runner saves the thread id to `reports/<slice>.thread`. With `--feedback FILE`, it resumes that thread using only feedback and a short fix assignment. Use `--fresh` to force a cold run with the full prompt plus feedback; a missing thread file also causes a cold run.

Change accounting compares working-tree snapshots before and after each run, includes untracked files, honors `.gitignore`, and excludes `.claude/handoff`. Temporary Git indexes leave your real index unchanged. `--scope` checks only this run's files; `--max-lines N` compares added + deleted lines with N and prints `within` or `OVER`. Neither warning changes Codex's exit code. The usage section prints the last token-usage object from the log, or `unavailable`.

For scout mode, write `<handoff-dir>/<slice-id>.md` with a question and the desired report format and length:

```bash
codex-slice.sh .claude/handoff/investigation Q1 --mode scout
```

Scout needs no `PLAN.md`, uses a `read-only` sandbox and [scout-charter.md](skills/opus-codex-flow/scout-charter.md), and prints only the report. It has no output schema, scope check, or change accounting. Claims carry `path:line` evidence; builds or tests run only when the question asks for them, and no fixes are proposed.

### Delegation policy

Direct work is the default, and the call is meant to be quick: Claude delegates only when it is an easy yes, and does the work itself when it is weighing it. The test is whether the handoff (a plan or brief, reading the report and diff, the acceptance runs) clearly costs less than doing the work. That tends to hold when the work is mostly iteration or bulk and the result can be stated as runnable acceptance commands. It is judged by difficulty and shape, not by line counts. Codex gets taste-light work: backend logic, tests, data plumbing, mechanical change, and broad read-only investigation. Small critical changes, docs and user-facing copy, GUI or real-device work, and undecided design stay with Claude. Two failed fix rounds or a plan that keeps growing means Claude takes over. [SKILL.md](skills/opus-codex-flow/SKILL.md) section 0 is the single source.

**Quota check.** `scripts/codex-quota.py` reads [CodexBar](https://github.com/steipete/CodexBar) and prints `QUOTA: ample|tight|unknown`. It uses the weekly window and CodexBar's pace (a linear estimate if the pace is missing):

| Codex tier | Remaining at least | Ahead of pace at most |
|---|---|---|
| pro | 40% | 10 points |
| plus, team, business, enterprise, edu | 60% | 5 points |
| free, go | never ample | n/a |

It is also `tight` when the short window is at 80% or more or CodexBar projects usage will not last to the reset. In the last quarter of the window, headroom that is about to expire counts for more: when usage is at least 10 points behind pace, the remaining floor drops to 15%. An unrecognised tier, stale window data or a missing CodexBar gives `unknown`. On `tight` or `unknown`, Claude does Codex-eligible work itself unless you invoked the skill or asked for Codex. Tune the tier limits with `OPUS_CODEX_FLOW_MIN_REMAINING` and `OPUS_CODEX_FLOW_MAX_AHEAD` (percent points).

**Claude subagents** are for keeping large raw output out of the main context or running independent questions in parallel. Claude chooses their model and effort by the task; the `digest` agent (Haiku, low effort, no edit tools) is a ready-made cheap option. The reliable gain is context isolation; a price gain from a cheaper model is unverified because subagent model routing has been unreliable in some versions ([anthropics/claude-code#43869](https://github.com/anthropics/claude-code/issues/43869)).

### Global CLAUDE.md block

A `SessionStart` hook keeps a short delegation block in `<CLAUDE_CONFIG_DIR or ~/.claude>/CLAUDE.md`. It summarises the policy and states that you installed the plugin to get this delegation and prefer it when it clearly pays off. That line exists because some Opus 5 builds have injected "Do not call the AgentTool unless the user requested it" ([#80988](https://github.com/anthropics/claude-code/issues/80988)), and the Agent tool's own text still says to spawn subagents only when the user asks. Whether a plugin-written line unlocks subagent spawning is unverified, so treat the Claude-subagent half as best effort. The Codex half runs through the skill and Bash and is not affected. When the hook writes, it shows you a one-line message.

The block sits between `<!-- opus-codex-flow:begin ... -->` and `<!-- opus-codex-flow:end -->` lines. It is added on the first session after install, refreshed when the plugin changes it, and never re-added after you remove it. If those lines are missing, duplicated or out of order, the file is left alone. Writes go through symlinks, keep CRLF line endings, and the first change saves `CLAUDE.md.opus-codex-flow.bak`. Set `OPUS_CODEX_FLOW_NO_CLAUDE_MD=1` to stop the hook from touching the file.

Claude Code has no uninstall hook, so removal is a step you trigger: run `/opus-codex-flow uninstall` (or `python3 skills/opus-codex-flow/scripts/sync-claude-md.py remove`) before `/plugin uninstall`. If you skip it, the block stays but says it applies only while the skill is available. `sync-claude-md.py add` puts it back.

### Customize taste

- Global rules: edit [taste-charter.md](skills/opus-codex-flow/taste-charter.md).
- Per-repo rules: add `<repo>/.claude/taste.md`; it is appended automatically.
- Per-task rules: the "Taste constraints" section of the plan.

When the same issue shows up in two reviews, add a rule instead of repeating the feedback.

## Notes and limits

- Taste is enforced by the charter plus Opus review. Nothing in the sandbox can enforce it.
- The charter's habit list is a practical heuristic from experience with GPT-family coding agents, not a measured benchmark. Tune it to what you actually see.
- `workspace-write` has no network. Slices that need installs or network access need you to relax the sandbox deliberately.
- Codex can lose cross-module wiring on long runs. Keep slices small and check the wiring.
- No public controlled comparison of "Opus plans + Codex builds" against a single model was found when this was written. Run it on a handful of your own tasks and compare cost and deviation before relying on it.

## Development

```
tests/smoke.sh      # runner, with a fake codex binary; no network, no tokens
tests/policy.sh     # quota gate (fake codexbar) and CLAUDE.md block
```

CI runs shellcheck, both test scripts, a Python compile check, and JSON validation of the manifests and hooks.

## License

MIT

---

## 中文说明

用 Claude Opus 规划与审查，用 Codex 实现。降低 Claude 消耗，同时把你的品位约束写进代码。

这是一个 Claude Code 插件，包含一个技能 `/opus-codex-flow`、一个小型子代理 `digest`（Haiku，无编辑工具）和一个 SessionStart 钩子：Opus 先写出明确的计划文件，脚本把每个切片交给计划里写明的 Codex 模型实现，Opus 再对照计划和品位章程审查 diff。

安装：

```
/plugin marketplace add LemonCANDY42/opus-codex-flow
/plugin install opus-codex-flow@opus-codex-flow
```

在 git 仓库里使用：`/opus-codex-flow <需求>`。

要点：

- 计划是文件，不靠对话上下文；行为、接口、兼容性、状态归属等决策都在计划里先定。
- 实现模式首次运行注入品位章程，禁止过度抽象、防御性兜底、兼容垫片、顺手改无关代码、复述型注释、只靠 mock 的测试、未接线的组件。
- 每个切片有路径范围和可执行的验收命令，不让模型自评。
- runner 默认 `--mode implement`，输出 JSON 报告、本轮 diff、增删行数、范围检查和 token 用量；`--max-lines N` 超限标记为 `OVER`，不改变退出码。
- `--feedback FILE` 默认续接已保存的线程，只发送反馈和简短任务；`--fresh` 强制重新发送完整提示，没有线程文件时也使用完整提示。
- `--mode scout` 只需 `<切片编号>.md` 问题文件，不需要 `PLAN.md`；只读调查，仅打印报告，每项结论附 `path:line`，不提出修复方案，除非问题明确要求，否则不运行构建或测试。
- 本轮改动统计包含未跟踪文件、遵守 `.gitignore`，使用临时 Git index，不改变真实暂存区；此前切片的改动不会被算入本轮范围检查。
- 每个切片最多 2 轮返工；提交和 PR 只在你要求时才做。
- 品位章程来自对 GPT 系编码代理的经验判断，不是实测基准，请按实际情况调整；也尚未找到公开的对照实验，建议先用自己的几个任务比较成本和偏离度。

委派策略：默认直接做，而且要快速判断：只有一眼就划算才委派，拿不准就自己做。判断标准是交接（写计划或任务说明、读报告和 diff、跑验收）是否明显比直接做便宜；这通常出现在工作以反复迭代或批量为主、结果又能写成可运行验收命令的时候。按难度和形态判断，不看行数。Codex 拿品位依赖低的工作：后端逻辑、测试、数据管线、机械改动和大范围只读调查。小而关键的改动、文档与面向用户的文字、图形界面或真机操作、设计未定的工作仍由 Claude 做。两轮返工仍失败或计划越写越长，就由 Claude 接手。唯一来源是 [SKILL.md](skills/opus-codex-flow/SKILL.md) 的 section 0。

额度检查：`scripts/codex-quota.py` 读取 CodexBar，输出 `QUOTA: ample|tight|unknown`，依据订阅档位、周窗口剩余比例和 CodexBar 的节奏（没有节奏数据时用线性估计）。pro 剩余至少 40%、领先节奏不超过 10 个百分点；plus、team 等其他付费档至少 60%、不超过 5 个百分点；free、go 不算富足。短窗口用量达 80%，或 CodexBar 预测额度撑不到重置，也是 `tight`。窗口最后四分之一里，即将过期的富余更值得用：用量落后节奏至少 10 个百分点时，剩余下限降到 15%。档位不认识、窗口数据过期或没有 CodexBar 为 `unknown`。`tight` 或 `unknown` 时 Claude 自己做，除非你手动调用技能或明确要求用 Codex。档位限值可用 `OPUS_CODEX_FLOW_MIN_REMAINING`、`OPUS_CODEX_FLOW_MAX_AHEAD` 调整。

Claude 子代理用于把大段原始输出挡在主上下文之外，或并行跑相互独立的问题；模型和强度由 Claude 按任务自己选，`digest`（Haiku、低强度、无编辑工具）是现成的便宜选项。可靠的收益是隔离上下文；更便宜模型带来的价格收益未验证，因为部分版本的子代理模型路由不可靠（[#43869](https://github.com/anthropics/claude-code/issues/43869)）。

全局 CLAUDE.md：`SessionStart` 钩子在 `<CLAUDE_CONFIG_DIR 或 ~/.claude>/CLAUDE.md` 里维护一段由 `opus-codex-flow:begin/end` 行围起来的委派规则（策略简版，外加一句“用户安装本插件就是为了这样委派，且在明显划算时倾向这样做”。个别 Opus 5 版本曾注入“用户没要求就不要调用 Agent 工具”，见 [#80988](https://github.com/anthropics/claude-code/issues/80988)，Agent 工具自身的说明也仍写着用户要求才派子代理。插件写的这句话能否解锁子代理未验证，所以 Claude 子代理这一半只是尽力而为；Codex 这一半走技能和 Bash，不受影响）。写入时会给你一行提示；安装后的第一个会话写入，插件更新时刷新，你删掉之后不会再自动加回；标记行缺失、重复或顺序不对时不改文件。写入会穿过软链接、保留 CRLF，首次修改会留 `CLAUDE.md.opus-codex-flow.bak`。设置 `OPUS_CODEX_FLOW_NO_CLAUDE_MD=1` 可让钩子不碰这个文件。Claude Code 没有卸载钩子，所以卸载前请先运行 `/opus-codex-flow uninstall`（或 `python3 skills/opus-codex-flow/scripts/sync-claude-md.py remove`）再 `/plugin uninstall`；没做的话这段规则会留下，但它自己写明“仅在该技能可用时适用”；`sync-claude-md.py add` 可以加回。使用模型自动调用模式时，仓库代码可能不经你逐次请求就通过 Codex 发给 OpenAI，不允许这样做的环境请不要启用本插件。

自定义品位：改 `taste-charter.md`（全局）、`<repo>/.claude/taste.md`（单仓库）、计划里的 "Taste constraints"（单任务）。
