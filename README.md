# opus-codex-flow

Plan and review with Claude Opus. Implement with Codex. Keep Claude spend low and keep your taste in the code.

A Claude Code plugin with one skill, `/opus-codex-flow`. Opus writes a precise plan, a small runner hands each slice to the Codex model the plan names, and Opus reviews the diff against the plan and a taste charter.

[中文说明](#中文说明)

## Why

Opus tends to make better design and taste decisions. A cheaper Codex model is good at the long typing-and-iterating part. The failure mode of splitting them is that any decision the plan leaves implicit gets filled in by the implementer's own habits. This project makes the handoff explicit:

- the plan is a file, not chat context, and resolves behavior, interface, compatibility and state-ownership decisions up front;
- each cold implement run gets a **taste charter** that names the habits to avoid (speculative abstraction, defensive padding, compatibility shims, scope creep, narrating comments, mock-only tests, unwired components);
- every slice has a path scope and acceptance **commands**, so pass/fail is not self-graded;
- Opus reads reports and diffs, not whole files, and gets a scope check for free.

## Install

Requires [Claude Code](https://claude.com/claude-code), the [Codex CLI](https://github.com/openai/codex) (`codex` on PATH, logged in), `git`, and `bash`.

```
/plugin marketplace add LemonCANDY42/opus-codex-flow
/plugin install opus-codex-flow@opus-codex-flow
```

## Use

In a git repository:

```
/opus-codex-flow add a 10% discount for orders of 10 or more units
```

The skill is explicit-invocation only, so it never hijacks ordinary work.

1. **Plan.** Opus investigates, then writes `.claude/handoff/<slug>/PLAN.md` from [plan-template.md](skills/opus-codex-flow/plan-template.md). See [examples/demo/PLAN.md](examples/demo/PLAN.md).
2. **Delegate.** For each slice Opus runs `scripts/codex-slice.sh`. It builds the prompt (charter + optional `<repo>/.claude/taste.md` + plan + assignment), runs `codex exec` with `-s workspace-write` and approvals off, and prints the JSON report, this run's diff and change size, a scope check, and usage.
3. **Review.** Opus runs the acceptance commands, reviews the diff against the plan's decisions and the charter, runs `--mode review` (read-only, a stronger model) once per PR, and either accepts or writes numbered feedback.
4. **Fix.** Feedback is re-run through the same script with `--feedback`, resuming the saved thread by default. At most two rounds per slice, then Opus takes over or escalates to you.
5. **Close.** Opus reports what changed, the evidence, plan deviations, and what is unverified. It commits or opens a PR only if you ask.

Trivial changes (about two files and thirty lines, no new logic) are done by Opus directly.

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
tests/smoke.sh      # uses a fake codex binary; no network, no tokens
```

CI runs shellcheck, the smoke test, and JSON validation of the manifests.

## License

MIT

---

## 中文说明

用 Claude Opus 规划与审查，用 Codex 实现。降低 Claude 消耗，同时把你的品位约束写进代码。

这是一个 Claude Code 插件，只有一个技能 `/opus-codex-flow`：Opus 先写出明确的计划文件，脚本把每个切片交给计划里写明的 Codex 模型实现，Opus 再对照计划和品位章程审查 diff。

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

自定义品位：改 `taste-charter.md`（全局）、`<repo>/.claude/taste.md`（单仓库）、计划里的 "Taste constraints"（单任务）。
