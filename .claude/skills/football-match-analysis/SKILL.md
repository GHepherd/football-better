---
name: football-match-analysis
description: 编排足球比赛分析全流程 —— 复盘已出结果的历史预测、采集赛前情报、产出概率分析、生成 ≤20 元竞彩足球投注方案。当用户点名一场或多场比赛（"分析一下阿森纳 vs 利物浦"）、要求出投注方案（"分析这几场，给我个方案"）、或询问该流程本身时使用。
---

# 足球比赛分析编排

本 skill 是足球分析流程的**默认入口**。它自己不分析任何东西 —— 它负责编排、交接、和把住闸门。

**铁律：不要自己重写任何阶段的领域逻辑。** 情报采集交给 `football-intelligence-gatherer`，概率分析交给 `football-match-analyzer`，投注方案交给 `lottery-strategist`，复盘交给 `football-match-reviewer`。这四个 agent 各自持有完整的领域规范。你自己写一遍只会产出更差的版本，并且与 agent 的记忆机制脱节。

**agent 仍可被单独直接触发**（例如只想补一次情报、或只想复盘某一场）。本 skill 是默认入口，不是唯一入口，两者不互斥。

## 核心机制：产物走文件，不走上下文

每个 agent **自己把产物写到磁盘**，只回传路径 + 3–5 行摘要。下一阶段 agent **从磁盘 Read** 上一阶段的文件，而不是从主会话接收全文。

不要因为"顺手"就把 agent 返回的长文粘进后续 prompt —— 那会让主会话被原始情报淹没，多场时尤其致命。

## 闸门与中止

**用户随时可以说「停」，停在哪一步就是哪一步。** 已落盘的产物保留，不清理、不回滚——它们就是这一步的真实状态，下一轮可接着用。

## 执行流程

### 第 0 步：复盘前置检查（条件执行）

复盘分**两轮，有先后依赖**：单场先评，方案要靠单场的结果才能放行。判定见 `references/review-protocol.md` 一。

#### 0a 单场队列

扫 `matches/` 下所有日期目录。一场比赛满足**全部三条**即为待复盘：

1. 存在 `<slug>-analysis.md`
2. 目录名的日期 **早于今天**（目录名即比赛日）
3. 不存在 `<slug>-review.md`

- 有 N 条 → dispatch `football-match-reviewer`（单场模式），每场一个。**可能修订同一条目（同一 agent 的同一主题）的场次必须串行**，不得并行；互不相干的场次可并行。详见 `references/review-protocol.md` 五
- prompt 中只给出该场 `-analysis.md` 的相对路径；**不要转述其内容**——让 reviewer 自己 Read，转述会污染它独立核对的判断
- 比赛未结束或查不到比分 → reviewer 会自行跳过且不写文件，这是预期行为，不要重试、不要报错

#### 0b 方案队列 —— 必须等 0a 全部落盘之后再扫

扫描时读每份 `plan-NN.md` 的**比赛清单那一段**（只为取值，**不要转述其余内容**）。一份方案满足**全部两条**即为待复盘：

1. 它「比赛清单」里的**每一场**都已有 `<slug>-review.md`
2. 不存在 `plan-NN-review.md`

- dispatch `football-match-reviewer`（方案模式），prompt 中只给出该 `plan-NN.md` 的相对路径，同样不转述内容
- **方案队列只在此时扫这一次，不要提前扫。** 提前扫有两个坏处：还差场次的方案会被误判进来；已经在 0a 之前判为待复盘的方案会被 dispatch 两次（第一次还没写出 `plan-NN-review.md`，第二次又判定它待复盘）
- 放在 0a 之后扫，也正是「本轮刚评完的比赛让某份方案凑齐放行条件」能在**同一次会话**里出分的原因；否则方案评分要拖到下一次会话

#### 通用

- **两个队列都为空 → 完全静默跳过**，不提、不问、不解释，直接进第 1 步。0a 为空时同样不要出声，直接做 0b
- 用户说"这次别复盘" → 两轮都跳过，且**不写**任何 review 文件，下次仍会提醒
- 方案被卡住时分两种，处理方式不同：**「某场未结束 / 查不到比分」→ 静默留着**（该场按 §三 不写 `-review.md`，方案自然不放行，这是设计使然）；**「比赛清单里的条目在盘上解析不到」→ 那是方案本身的缺陷，必须报给用户**，不要静默重试——它永远不会自己好

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

全部完成后，**主会话**按比赛日分组，把该日全部 `-analysis.md` 汇总成**该日目录下的** `matches/<比赛日>/summary.md`（每个比赛日一份；单场也写，保持产物一致）。跨比赛日的批次产出多份 `summary.md`，**不得合并成一份**。

交接契约见 `references/handoff-contracts.md`。

### 第 4 步：投注方案 ⏸ 硬闸门

**在 dispatch `lottery-strategist` 之前，必须停下来问用户是否要出体彩方案。**

这是不可逆的真实支出，规则没有例外：

- 每次都要显式征求同意，**上一轮的同意不延续到下一轮**
- 用户没明确说要 → 绝不进这一步，流程在第 3 步结束
- 用户回答「要」→ dispatch 一个 `lottery-strategist`，prompt 中给出**本轮全部** `summary.md` 的相对路径（跨比赛日时逐个列出，不代抄其内容，让 agent 自己 Read），以及**产物路径**。方案文档落在本轮**最早**的那个比赛日目录，命名为 `plan-NN.md`：先 `ls` 该目录下已有的 `plan-NN.md`（**只认方案本体**，`plan-*.md` 会连 `plan-NN-review.md` 一起匹配到，review 不占号），取下一个可用序号（一个都没有就用 `plan-01.md`）——**绝不覆盖已有方案**。要求 agent 把完整方案写入该文件，回执中只返回路径 + 摘要

## 产物与命名

```
matches/YYYY-MM-DD/
├── <slug>-intel.md        # gatherer 产出
├── <slug>-analysis.md     # analyzer 产出
├── <slug>-review.md       # reviewer 产出（单场复盘）
├── summary.md             # 主会话汇总
├── plan-NN.md             # strategist 产出（仅在用户同意后；同一天多份则 01/02/…）
└── plan-NN-review.md      # reviewer 产出（方案复盘，覆盖的各场都复盘完之后才写）
```

slug = `<主队>-vs-<客队>`，全小写、连字符分隔。日期目录用**比赛日**，不是分析日。

路径一律用相对路径书写；`Write` 工具要求绝对路径，调用前先解析。可用 `scripts/new-match-dir.sh YYYY-MM-DD` 建目录（可选，`Write` 本身也会自建目录）。

## 引用文档

- `references/handoff-contracts.md` —— dispatch 任一阶段 agent **之前**读，确认交接字段齐全
- `references/review-protocol.md` —— 第 0 步判定待复盘、或用户直接要复盘时读
- `references/artifact-templates.md` —— 写任何产物文件**之前**读

## 语言

跟随用户语言。竞彩术语（胜平负、让球胜平负、混合过关等）一律用中文。
