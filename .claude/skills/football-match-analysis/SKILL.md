---
name: football-match-analysis
description: 编排足球比赛分析全流程 —— 复盘已出结果的历史预测、采集赛前情报、产出概率分析、生成 ≤20 元竞彩足球投注方案。当用户点名一场或多场比赛（"分析一下阿森纳 vs 利物浦"）、要求出投注方案（"分析这几场，给我个方案"）、或询问该流程本身时使用。
---

# 足球比赛分析编排

本 skill 是足球分析流程的**默认入口**。它自己不分析任何东西 —— 它负责编排、交接、和把住闸门。

**铁律：不要自己重写任何阶段的领域逻辑。** 情报采集交给 `football-intelligence-gatherer`，概率分析交给 `football-match-analyzer`，投注方案交给 `lottery-strategist`，复盘交给 `football-match-reviewer`。这四个 agent 各自持有完整的领域规范。你自己写一遍只会产出更差的版本，并且与 agent 的记忆机制脱节。

## 核心机制：产物走文件，不走上下文

每个 agent **自己把产物写到磁盘**，只回传路径 + 3–5 行摘要。下一阶段 agent **从磁盘 Read** 上一阶段的文件，而不是从主会话接收全文。

不要因为"顺手"就把 agent 返回的长文粘进后续 prompt —— 那会让主会话被原始情报淹没，多场时尤其致命。

## 执行流程

### 第 0 步：复盘前置检查（条件执行）

扫 `matches/` 下所有日期目录。一场比赛满足**全部三条**即为待复盘：

1. 存在 `<slug>-analysis.md`
2. 目录名的日期 **早于今天**（目录名即比赛日）
3. 不存在 `<slug>-review.md`

- 有 N 条待复盘 → dispatch `football-match-reviewer`，每场一个（可并行）
- **一条都没有 → 完全静默跳过**，不提、不问、不解释，直接进第 1 步
- 用户说"这次别复盘" → 跳过，且**不写** `-review.md`，下次仍会提醒
- 比赛未结束或查不到比分 → reviewer 会自行跳过且不写文件，这是预期行为，不要重试、不要报错

细节与校准口径见 `references/review-protocol.md`。

### 第 1 步：确认场次清单

- 单场 → 从用户话里直接取，不必反问
- 多场 → 先列出你理解到的清单（队名 + 比赛日），请用户确认或增删
- 用户没给比赛日、或同一对阵有多个日期 → 必须问清

### 第 2 步：采集情报

每场 dispatch 一个 `football-intelligence-gatherer`。**多场时在同一条消息里发出全部调用**，让它们并行跑。

prompt 中给出：比赛（主队 vs 客队）、赛事、比赛日，以及**产物落盘路径** `matches/<比赛日>/<slug>-intel.md`，要求 agent 把完整情报写入该文件，并在回执中只返回路径 + 摘要。

### 第 3 步：概率分析

每场 dispatch 一个 `football-match-analyzer`。同样并行。

prompt 中给出：对应 `-intel.md` 的路径（要求 agent 自己 Read），以及产物路径 `matches/<比赛日>/<slug>-analysis.md`。

全部完成后，**主会话**把所有 `-analysis.md` 汇总成 `matches/<比赛日>/summary.md`（单场也写，保持产物一致）。

交接契约见 `references/handoff-contracts.md`。

### 第 4 步：投注方案 ⏸ 硬闸门

**在 dispatch `lottery-strategist` 之前，必须停下来问用户是否要出体彩方案。**

这是不可逆的真实支出，规则没有例外：

- 每次都要显式征求同意，**上一轮的同意不延续到下一轮**
- 用户没明确说要 → 绝不进这一步，流程在第 3 步结束
- 用户回答「要」→ dispatch 一个 `lottery-strategist`，prompt 中给出 `summary.md` 路径与产物路径 `matches/<比赛日>/plan.md`

## 产物与命名

```
matches/YYYY-MM-DD/
├── <slug>-intel.md        # gatherer 产出
├── <slug>-analysis.md     # analyzer 产出
├── <slug>-review.md       # reviewer 产出（复盘）
├── summary.md             # 主会话汇总
└── plan.md                # strategist 产出（仅在用户同意后）
```

slug = `<主队>-vs-<客队>`，全小写、连字符分隔。日期目录用**比赛日**，不是分析日。

路径一律用相对路径书写；`Write` 工具要求绝对路径，调用前先解析。可用 `scripts/new-match-dir.sh YYYY-MM-DD` 建目录（可选，`Write` 本身也会自建目录）。

## 引用文档

- `references/handoff-contracts.md` —— dispatch 任一阶段 agent **之前**读，确认交接字段齐全
- `references/review-protocol.md` —— 第 0 步判定待复盘、或用户直接要复盘时读
- `references/artifact-templates.md` —— 写任何产物文件**之前**读

## 语言

跟随用户语言。竞彩术语（胜平负、让球胜平负、混合过关等）一律用中文。
