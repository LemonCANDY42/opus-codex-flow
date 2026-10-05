# opus-codex-flow

Plan and review with Claude Opus. Implement with Codex. Keep Claude spend low and keep your taste in the code.

A Claude Code plugin with one skill, `/opus-codex-flow`. Opus writes a precise plan, a small runner hands each slice to a Codex model (default `gpt-6.1-sol`), and Opus reviews the diff against the plan and a taste charter.

[中文说明](#中文说明)

## Why

Opus tends to make better design and taste decisions. A cheaper Codex model is good at the long typing-and-iterating part. The failure mode of splitting them is that any decision the plan leaves implicit gets filled in by the implementer's own habits. This project makes the handoff explicit:

- the plan is a file, not chat context, and resolves behavior, interface, compatibility and state-ownership decisions up front;
- every Codex run gets a **taste charter** that names the habits to avoid (speculative abstraction, defensive padding, compatibility shims, scope creep, narrating comments, mock-only tests, unwired components);
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
2. **Delegate.** For each slice Opus runs `scripts/codex-slice.sh`. It builds the prompt (charter + optional `<repo>/.claude/taste.md` + plan + assignment), runs `codex exec` with `-s workspace-write` and approvals off, and prints only the final report, the diff stat, and an out-of-scope file check.
3. **Review.** Opus runs the acceptance commands, reviews the diff against the plan's decisions and the charter, optionally adds a read-only reviewer agent, and either accepts or writes numbered feedback.
4. **Fix.** Feedback is re-run through the same script with `--feedback`. At most two rounds per slice, then Opus takes over or escalates to you.
5. **Close.** Opus reports what changed, the evidence, plan deviations, and what is unverified. It commits or opens a PR only if you ask.

Trivial changes (about two files and thirty lines, no new logic) are done by Opus directly.

### Runner

```
codex-slice.sh <handoff-dir> <slice-id> [--scope "glob,glob"] [--feedback FILE]
               [--model M] [--effort E] [--repo DIR]
```

Defaults: model `gpt-6.1-sol` (env `CODEX_SLICE_MODEL`), effort `high` (env `CODEX_SLICE_EFFORT`). Use `--effort xhigh` for cross-layer or UI work. Each run writes `reports/<slice>.runN.{md,log,prompt.md}` under the handoff directory. The model slug must exist in your Codex install; check `~/.codex/models_cache.json`.

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
- The runner calls `git add -N .` so new files appear in the diff. This marks files intent-to-add in your index; it does not stage content.
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

这是一个 Claude Code 插件，只有一个技能 `/opus-codex-flow`：Opus 先写出明确的计划文件，脚本把每个切片交给 Codex 模型（默认 `gpt-6.1-sol`）实现，Opus 再对照计划和品位章程审查 diff。

安装：

```
/plugin marketplace add LemonCANDY42/opus-codex-flow
/plugin install opus-codex-flow@opus-codex-flow
```

在 git 仓库里使用：`/opus-codex-flow <需求>`。

要点：

- 计划是文件，不靠对话上下文；行为、接口、兼容性、状态归属等决策都在计划里先定。
- 每次 Codex 运行都会注入品位章程，禁止过度抽象、防御性兜底、兼容垫片、顺手改无关代码、复述型注释、只靠 mock 的测试、未接线的组件。
- 每个切片有路径范围和可执行的验收命令，不让模型自评。
- 每个切片最多 2 轮返工；提交和 PR 只在你要求时才做。
- 品位章程来自对 GPT 系编码代理的经验判断，不是实测基准，请按实际情况调整；也尚未找到公开的对照实验，建议先用自己的几个任务比较成本和偏离度。

自定义品位：改 `taste-charter.md`（全局）、`<repo>/.claude/taste.md`（单仓库）、计划里的 "Taste constraints"（单任务）。
