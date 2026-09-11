# 足球比赛分析编排 Skill 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把仓库里三个各自独立的足球分析 agent 用一个编排 skill 串起来，并新增复盘 agent 补上"预测 → 实际 → 校准 → 回写记忆"的闭环。

**Architecture:** 新增 `.claude/skills/football-match-analysis/` 作为唯一入口，薄 `SKILL.md` 承载四阶段编排与确认闸门，细节落在 `references/` 下的三份文档（渐进式披露）。阶段之间**通过磁盘文件交接，不走主会话上下文** —— 每个 agent 自己写产物、只回传路径与摘要。新增第 4 个 agent `football-match-reviewer` 承担复盘。

**Tech Stack:** 纯 Markdown 配置 + Bash。无构建、无依赖、无测试框架（本仓库刻意如此，见 `CLAUDE.md`）。验证靠 `python3` 解析 YAML frontmatter、`grep` 断言、以及最后的手动冒烟测试。

**Spec:** `docs/superpowers/specs/2026-09-11-football-match-analysis-skill-design.md`

## Global Constraints

- **本仓库没有测试框架**，不要引入。验证步骤用 `python3` / `grep` / 手动执行，不新增 test 目录、不新增 CI 配置。
- **路径一律相对项目根目录书写**。`Write` 工具要求绝对路径，所以在真正调工具时才解析。任何 manifest / SKILL.md 里**不得出现** `/Users/sheoherd/...` 这类硬编码绝对路径。
- **不要动三个现有 agent 的领域指令正文**（各自约 200 行）。本次对它们的改动仅限 Task 1 范围内的路径与过时句子。
- **提交时用精确路径 `git add <file>`，禁止 `git add -A` / `git add .`**。工作区当前有无关的脏改动（`.claude/settings.local.json` 被修改、`match-analysis-2026-06-26.md` 被删除），绝不能卷进本次提交。
- **产物路径命名固定**：`matches/YYYY-MM-DD/<slug>-intel.md` / `-analysis.md` / `-review.md`，以及 `matches/YYYY-MM-DD/summary.md`、`plan.md`。slug 格式 `<主队>-vs-<客队>`，全小写连字符。
- **`matches/` 默认提交**（仓库无 `.gitignore`，不新增）。`-review.md` 是校准闭环的证据，必须入库。
- 所有面向用户的文本遵循仓库既有约定：跟用户语言（中文或英文）。
- **验证命令里不要用裸 `cd`**：Bash 工具的工作目录在调用之间保持，一次 `cd /tmp` 会让后续所有步骤静默跑错目录。需要换目录时用子 shell `( cd ... && ... )`，或直接用绝对路径。

---

### Task 1: 修复三个现有 agent 的记忆路径

**Files:**
- Modify: `.claude/agents/football-intelligence-gatherer.md:79`
- Modify: `.claude/agents/football-match-analyzer.md:124`
- Modify: `.claude/agents/lottery-strategist.md:74`
- Modify: `.claude/agents/football-intelligence-gatherer.md:213`
- Modify: `.claude/agents/football-match-analyzer.md:258`
- Modify: `.claude/agents/lottery-strategist.md`（末尾同位置）

**Interfaces:**
- Consumes: 无（第一个任务）
- Produces: 三个 agent 使用可移植的相对路径 `.claude/agent-memory/<agent>/`。后续所有任务引用的路径格式以此为准。

**背景：** 三份 manifest 都把记忆目录写死成 `/Users/sheoherd/Desktop/football/.claude/agent-memory/<agent>/`，但仓库实际在 `/Users/sheoherd/Desktop/f/` —— 这个路径**从来就没对过**，换机器更必然失效。三份末尾还都写着「Your MEMORY.md is currently empty」，而实际三个 `MEMORY.md` 都已有内容。

- [ ] **Step 1: 确认当前坏路径的确切文本**

Run:
```bash
grep -n "Desktop/football" .claude/agents/*.md
grep -n "currently empty" .claude/agents/*.md
```
Expected: 3 处 `Desktop/football`（每份 manifest 各一行），3 处 `currently empty`。记下确切的引号与措辞，下一步要精确替换。

- [ ] **Step 2: 替换记忆目录路径**

三份 manifest 中，把这一行：

```
You have a persistent, file-based memory system at `/Users/sheoherd/Desktop/football/.claude/agent-memory/football-intelligence-gatherer/`. This directory already exists — write to it directly with the Write tool (do not run mkdir or check for its existence).
```

替换为（注意 agent 名要各自对应）：

```
You have a persistent, file-based memory system at `.claude/agent-memory/football-intelligence-gatherer/`, relative to the project root. This directory already exists — write to it directly with the Write tool.

The `Write` tool requires an absolute path, so resolve this relative path against the current working directory before calling it (e.g. confirm with `pwd`). Never hardcode an absolute path into a memory file or into this manifest — the project must work from any clone location and any machine.
```

`football-match-analyzer.md` 和 `lottery-strategist.md` 同样处理，替换为各自的目录名。

- [ ] **Step 3: 删除过时的 MEMORY.md 说明**

三份 manifest 末尾的：

```
## MEMORY.md

Your MEMORY.md is currently empty. When you save new memories, they will appear here.
```

替换为：

```
## MEMORY.md

Your MEMORY.md is an index of your existing memories. Read it at the start of a task and keep it updated — add one line per new memory, and remove lines whose memory you deleted. Do not write memory content directly into it.
```

- [ ] **Step 4: 验证没有遗漏**

Run:
```bash
grep -rn "Desktop/football" .claude/agents/ ; echo "exit=$?"
grep -rn "currently empty" .claude/agents/ ; echo "exit=$?"
grep -c "relative to the project root" .claude/agents/*.md
```
Expected: 前两条 grep 无输出（exit=1）；第三条三个文件各输出 `1`。

- [ ] **Step 5: 验证领域正文未被误伤**

Run:
```bash
git diff --stat .claude/agents/
```
Expected: 三个文件各为 `+N -M` 的小改动（N、M 分别在 10 行内）。**若某个文件 diff 超过约 30 行，说明替换范围失控，回退重做。**

- [ ] **Step 6: 提交**

```bash
git add .claude/agents/football-intelligence-gatherer.md .claude/agents/football-match-analyzer.md .claude/agents/lottery-strategist.md
git commit -m "fix(agents): use project-relative memory paths in the three football agents"
```

---

### Task 2: 新增复盘 agent `football-match-reviewer`

**Files:**
- Create: `.claude/agents/football-match-reviewer.md`

**Interfaces:**
- Consumes: Task 1 确立的相对路径约定（`.claude/agent-memory/football-match-reviewer/`）
- Produces: agent 名 `football-match-reviewer`，供 Task 3 的 SKILL.md 通过 Agent 工具以 `subagent_type: "football-match-reviewer"` 调用。其产物文件名固定为 `<slug>-review.md`，格式见 Step 3。

**说明：** 这份 manifest **不复用**那三个老 manifest 里逐字重复的约 130 行通用记忆样板，而是写一段针对复盘的记忆指引。理由见 spec §5.4。

- [ ] **Step 1: 创建 manifest，写入 frontmatter 与身份**

创建 `.claude/agents/football-match-reviewer.md`，内容以以下开头：

```markdown
---
name: "football-match-reviewer"
description: "Use this agent when already-completed football matches have frozen predictions on disk that have not yet been reviewed, or when the user asks how accurate previous predictions turned out. It grades frozen predictions against actual results, computes calibration metrics, attributes the error, and writes the lessons back into agent memory.\\n\\n<example>\\nContext: The user is starting a new round of analysis and last week's matches have all finished.\\nuser: \\\"分析一下这周末的几场\\\"\\nassistant: \\\"先让 football-match-reviewer 复盘上一批已出结果的预测，再开始新的分析。\\\"\\n<commentary>\\nmatches/ 下存在有 analysis 无 review 且比赛日已过的文件，先复盘再分析。\\n</commentary>\\n</example>\\n\\n<example>\\nContext: The user asks how accurate the previous predictions were.\\nuser: \\\"上次那几场准不准？\\\"\\nassistant: \\\"我用 football-match-reviewer 把上次的预测和实际结果逐场比对，给出校准报告。\\\"\\n<commentary>\\n用户直接索要复盘，这是 reviewer 的核心职能。\\n</commentary>\\n</example>"
model: inherit
color: yellow
memory: project
---

You are an elite sports betting model auditor. Your entire value comes from one property: **you grade predictions you did not make and cannot change.** The predictions you review are frozen in `-analysis.md` files on disk, written before kickoff. You never re-derive them, never rationalise them, and never soften a miss. Your job is to find out where the model was wrong and why.
```

- [ ] **Step 2: 写入核心流程**

在 frontmatter 之后追加：

```markdown
## Your Core Mission

Given a completed match with a frozen prediction file, determine: (a) how well-calibrated the prediction was, (b) whether any recommended bet won, (c) **why** the model was right or wrong, and (d) what should change in agent memory as a result.

## Input

You will be given the path to a `<slug>-analysis.md` file. Read it. It contains the frozen prediction: 1X2 probabilities, top-10 correct scores, Asian handicap lines, and total-goals lines. If a `plan.md` exists in the same directory and covers this match, read it too.

If the user supplies actual scores directly, use them and say so in the report. Otherwise retrieve results via **WebSearch** — WebFetch is blocked for essentially all football data domains (sportsmole, espn, uefa.com, whoscored all fail with "Unable to verify if domain is safe to fetch"), so do not waste calls on it. Use targeted searches for the final score, half-time score, and key events.

## Procedure

### Step 1: Extract the frozen prediction
Pull out, verbatim from the file: the three 1X2 probabilities, the top-10 correct-score table, the handicap line(s) and side probabilities, the total-goals lines, the stated intelligence confidence (High/Medium/Low), and any recommended bet with its stated minimum odds.

### Step 2: Retrieve the actual result
Final score, half-time score, and material events (red cards, injuries that forced early subs, penalties). Record your source and how confident you are in it. If the match has **not finished**, or you cannot find a reliable final score: **stop, produce no review file, and report that the match remains pending.** Never write a `-review.md` on an unfinished match — that would permanently retire it from the review queue.

### Step 3: Compute calibration metrics

**1X2 — always compute both, and always report them against the uniform baseline:**

- **Brier score** (multi-class, single match): `BS = Σ_k (p_k − o_k)²` over k ∈ {Home, Draw, Away}, where `p_k` is the predicted probability and `o_k` is 1 for the actual outcome, 0 otherwise. Range 0–2, lower is better.
- **Log loss**: `−ln(p_actual)`, using the predicted probability of the outcome that actually occurred. Lower is better.
- **Baseline for comparison**: uniform 1/3 on each outcome gives `BS ≈ 0.667` and `log loss ≈ 1.0986`. **A Brier score of 0.55 is meaningless until it is placed against this baseline.** Always print both the model's number and the baseline.

**Other markets — hit/miss only, do not invent scores:**

- **Correct score**: was the actual score inside the top-10 table? What probability did the model assign to the actual score (including the "other scores" bucket if outside)?
- **Asian handicap**: did the chosen side win, lose, or push (走盘)? Report the result, not a score.
- **Total goals**: did over/under hit at the primary line?

**Recommended bet, if one was made**: did it win? Compute the P&L at the odds actually available at the time, not at the model's minimum acceptable odds. If a `plan.md` exists, report the total 20-yuan stake, the return, and the recovery rate.

### Step 4: Attribute the error — this is the actual deliverable
Reporting hit/miss is bookkeeping. **Attribution is the point.** Identify which specific piece of intelligence or which modelling assumption failed:

- Was a lineup or injury call wrong? (compare the `CONFIRMED`/`REPORTED`/`PREDICTED` tags in the intel file against what actually happened on the pitch)
- Was a rotation or motivation assumption wrong?
- Was the market simply right and the model's "value" illusory?
- Was the λ (expected goals) estimate biased for this team/league/profile?

If the prediction was correct, say whether it was correct for the stated reason or by luck — a right answer from a wrong mechanism is still a defect.

### Step 5: Write the review file
Write `matches/<date>/<slug>-review.md` using the structure in `references/artifact-templates.md`.

### Step 6: Write back to memory
See the memory rules below.

## Sample Size Discipline

**When n < 5 comparable observations, every conclusion must be explicitly labelled 「样本不足，仅作观察」(insufficient sample, observation only), and you must NOT adjust any parameter, λ, or probability offset on the basis of it.** Small-sample noise being promoted to a rule is how a model degrades. The precedent is in the analyzer's memory: `extreme-mismatch-ucl` was downgraded to "待验证" after n=2 failures — that is the correct behaviour for small n.

## Memory Write Permission

You have a deliberate and **narrowly bounded** authority that no other agent has: you may amend the *evidence* annotations on memory entries belonging to the other agents.

**You MAY:**
- Append or update evidence on an existing entry — the n count, the win/loss record, a confidence upgrade or downgrade (e.g. adding "⚠️ 2026-09-11 实战 n=3 中 2 次失败，降级为待验证" to an existing claim).
- Correct an evidence annotation you previously wrote when more data arrives.

**You MUST NOT:**
- Silently rewrite the original claim itself. If the evidence is strong enough to overturn a claim, **write a new memory and link the old one** with `[[old-entry-name]]`, preserving the reasoning trail. Silent edits destroy the audit trail that makes this whole loop trustworthy.
- Touch anything outside the "evidence/confidence" portion of an entry.

Every amendment must be listed in the review file's 「本轮记忆修订」 section — which entry, what changed, and why.

**Why this matters:** the analyzer's memory holds *hypotheses* ("小球常被高估"). Only match results produce *evidence*. If you cannot downgrade a hypothesis, wrong ones accumulate forever and the calibration loop is broken. This is exactly what the user was doing by hand before this agent existed.

## Update your agent memory

Write memories about **calibration methodology**, not about individual match outcomes — individual outcomes belong in the `-review.md` file, which is already durable on disk.

Record things like:
- Markets or match profiles where your Brier score is systematically worse than baseline
- Recurring attribution patterns (e.g. "lineup uncertainty in this league consistently costs the most calibration")
- Leagues/competitions where results are hard to source reliably via WebSearch
- Which existing memory entries have accumulated enough evidence to be promoted, and which remain unvalidated

Do **not** save: individual match scores, the contents of a review file, or anything derivable by reading `matches/`.

## Language

Respond in the same language the user uses — Chinese for Chinese, English for English.
```

- [ ] **Step 3: 验证 frontmatter 可解析且字段完整**

Run:
```bash
python3 - <<'PY'
import re, sys, pathlib
p = pathlib.Path(".claude/agents/football-match-reviewer.md")
t = p.read_text()
m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
assert m, "frontmatter missing or malformed"
fm = m.group(1)
for k in ("name:", "description:", "model:", "color:", "memory:"):
    assert k in fm, f"missing field {k}"
assert 'name: "football-match-reviewer"' in fm, "name mismatch"
print("OK frontmatter; body lines:", len(t.splitlines()) - len(m.group(0).splitlines()))
PY
```
Expected: `OK frontmatter; body lines: <n>`，n 在 100–180 之间。

- [ ] **Step 4: 验证不含硬编码绝对路径**

Run:
```bash
grep -n "/Users/" .claude/agents/football-match-reviewer.md ; echo "exit=$?"
```
Expected: 无输出（exit=1）。

- [ ] **Step 5: 提交**

```bash
git add .claude/agents/football-match-reviewer.md
git commit -m "feat(agents): add football-match-reviewer agent for calibration review"
```

---

### Task 3: 创建 skill 骨架与 `SKILL.md`

**Files:**
- Create: `.claude/skills/football-match-analysis/SKILL.md`
- Create: `.claude/skills/football-match-analysis/scripts/new-match-dir.sh`

**Interfaces:**
- Consumes: Task 2 的 agent 名 `football-match-reviewer`；三个既有 agent 名 `football-intelligence-gatherer` / `football-match-analyzer` / `lottery-strategist`
- Produces: skill 名 `football-match-analysis`；引用的两个 references 文件路径（由 Task 4–6 创建）；产物路径约定

- [ ] **Step 1: 创建目录**

```bash
mkdir -p .claude/skills/football-match-analysis/references .claude/skills/football-match-analysis/scripts
```

- [ ] **Step 2: 写 `SKILL.md`**

创建 `.claude/skills/football-match-analysis/SKILL.md`：

```markdown
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

细节与校借口径见 `references/review-protocol.md`。

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
```

- [ ] **Step 3: 写 `scripts/new-match-dir.sh`**

创建 `.claude/skills/football-match-analysis/scripts/new-match-dir.sh`：

```bash
#!/usr/bin/env bash
# 幂等创建 matches/YYYY-MM-DD/ 目录。
# 用法: scripts/new-match-dir.sh 2026-09-11
# 注意: Write 工具本身会自建目录，这个脚本只是让"建目录"这一步在 shell 里显式可见。
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "用法: $0 YYYY-MM-DD" >&2
  exit 2
fi

date_dir="$1"
if ! printf '%s' "$date_dir" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "错误: 日期必须是 YYYY-MM-DD 格式，收到 '$date_dir'" >&2
  exit 2
fi

mkdir -p "matches/$date_dir"
echo "matches/$date_dir"
```

```bash
chmod +x .claude/skills/football-match-analysis/scripts/new-match-dir.sh
```

- [ ] **Step 4: 验证 frontmatter 与 skill 可被发现**

Run:
```bash
python3 - <<'PY'
import re, pathlib
p = pathlib.Path(".claude/skills/football-match-analysis/SKILL.md")
t = p.read_text()
m = re.match(r"^---\n(.*?)\n---\n", t, re.S)
assert m, "frontmatter missing"
fm = m.group(1)
assert "name: football-match-analysis" in fm, "name must match the directory name"
assert "description:" in fm, "description is required for skill discovery"
print("OK skill frontmatter")
PY
```
Expected: `OK skill frontmatter`

- [ ] **Step 5: 验证脚本幂等**

Run:
**重要：用子 shell 做，不要 `cd`。** Bash 工具的工作目录在调用之间是**保持**的，一旦 `cd /tmp` 就会让后续所有步骤静默地跑在错误的目录里。下面全程用 `( ... )` 子 shell 包裹，或显式使用绝对路径。

```bash
SCRIPT="$PWD/.claude/skills/football-match-analysis/scripts/new-match-dir.sh"
rm -rf /tmp/skill-smoke && mkdir -p /tmp/skill-smoke
( cd /tmp/skill-smoke && bash "$SCRIPT" 2026-09-11 )
( cd /tmp/skill-smoke && bash "$SCRIPT" 2026-09-11 )
test -d /tmp/skill-smoke/matches/2026-09-11 && echo "idempotent OK"
( cd /tmp/skill-smoke && bash "$SCRIPT" 26-9-11 ) ; echo "bad-input exit=$?"
rm -rf /tmp/skill-smoke
```
Expected: 两次输出 `matches/2026-09-11`，`idempotent OK`，非法输入打印错误并以 `exit=2` 结束。执行完 `pwd` 应仍在仓库根目录。

- [ ] **Step 6: 提交**

```bash
git add .claude/skills/football-match-analysis/SKILL.md .claude/skills/football-match-analysis/scripts/new-match-dir.sh
git commit -m "feat(skills): add football-match-analysis orchestration skill"
```

---

### Task 4: 写 `references/handoff-contracts.md`

**Files:**
- Create: `.claude/skills/football-match-analysis/references/handoff-contracts.md`

**Interfaces:**
- Consumes: Task 3 在 SKILL.md 中对该路径的引用
- Produces: 阶段间必填字段清单，被 SKILL.md 第 2/3 步引用

- [ ] **Step 1: 写入内容**

```markdown
# 阶段交接契约

每个阶段 agent 只在上一步交齐字段后才开工。缺字段时**显式报告缺什么、影响哪些结论**，不要静默补全。

---

## gatherer → analyzer

analyzer 从 `matches/<date>/<slug>-intel.md` 读取。必填：

| 字段 | 说明 |
|---|---|
| 两队近 10 场 | 比分、对手、**主客场分离** |
| H2H | 近 5–10 次交锋，注明赛事与主客场 |
| 赔率 | 欧赔 1X2 与亚盘让球；**必须注明采集时点** |
| 阵容 / 伤停 | 确认首发或预测首发，逐项列出 |

**每个数据点必须带可信度标记**：`CONFIRMED` / `REPORTED` / `PREDICTED`。

**缺项处理：** analyzer 必须在报告开头显式列出「因缺 X，以下概率不可信」，并点名受影响的市场。静默用默认值补全是最严重的失败模式 —— 它把不确定性伪装成了确定性。

**已知数据源约束：** WebFetch 对绝大多数体育域名被封（sportsmole、espn、uefa.com、whoscored 等均返回 "Unable to verify if domain is safe to fetch"）。情报一律走 WebSearch，通常 5–7 轮针对性查询可覆盖赔率、阵容、伤停、近期状态、H2H。

---

## analyzer → strategist

strategist 从 `matches/<date>/summary.md` 读取。每场必填：

| 字段 | 说明 |
|---|---|
| 1X2 概率 | 三项，和为 100% |
| 正确比分 | 前 10 项，覆盖约 85%+ |
| 让球 | 主线及相邻线，两侧概率 |
| 总进球 | 至少 2.5 线，含 1.5 / 3.5 |
| 情报完整度 | **高 / 中 / 低** |
| 边际价值结论 | 有 / 无；有则指明市场 |

**缺项处理：** 情报完整度为「**低**」时，strategist 必须降级为保守方案，或明确建议观望。**不得基于低完整度数据出激进过户（3串1 及以上）。** 这是硬约束，不是建议。

---

## analyzer → reviewer

reviewer **直接 Read** `-analysis.md` 原始文件，不走主会话转述 —— 转述会引入二次失真，而且盘上那份才是冻结的事实。

必填（即 reviewer 要提取的字段）：

| 字段 | 说明 |
|---|---|
| 1X2 三项概率 | 用于算 Brier score 与 log loss |
| 正确比分前 10 | 含「其他比分」桶的概率 |
| 让球线及两侧概率 | 含主线 |
| 总进球线 | 至少主线的 over/under |
| 情报完整度 | 高 / 中 / 低 |
| 推荐（若有） | 市场、概率、最低可接受赔率 |

**缺项处理：** 某一市场缺失 → reviewer 在报告中标注「该市场本轮无法评估」，**但不得因此跳过整场复盘**。其余能评估的市场照常出结论。

---

## 契约的稳定性

以上字段是**接口**。改它们等于改四个 agent 的对接方式 —— 改之前先确认所有相关 agent 都能跟上，并同步更新本文件与 `artifact-templates.md`。
```

- [ ] **Step 2: 验证**

Run:
```bash
test -f .claude/skills/football-match-analysis/references/handoff-contracts.md && echo "exists"
grep -c "^## " .claude/skills/football-match-analysis/references/handoff-contracts.md
grep -q "CONFIRMED" .claude/skills/football-match-analysis/references/handoff-contracts.md && echo "tags OK"
grep -q "不得基于低完整度数据出激进过户" .claude/skills/football-match-analysis/references/handoff-contracts.md && echo "hard-constraint OK"
```
Expected: `exists`、`5`（五个 `## ` 标题）、`tags OK`、`hard-constraint OK`

- [ ] **Step 3: 提交**

```bash
git add .claude/skills/football-match-analysis/references/handoff-contracts.md
git commit -m "docs(skills): add stage handoff contracts"
```

---

### Task 5: 写 `references/artifact-templates.md`

**Files:**
- Create: `.claude/skills/football-match-analysis/references/artifact-templates.md`

**Interfaces:**
- Consumes: Task 4 定义的文件名与字段
- Produces: 四类产物的骨架，被 SKILL.md 与 reviewer manifest 引用

- [ ] **Step 1: 写入内容**

内容为四类产物的骨架：`-intel.md`、`-analysis.md`、`-review.md`、`summary.md`。

要点（写进文件正文）：

- `-intel.md` —— 沿用 `football-intelligence-gatherer` manifest 里的 Output Format（四个情报分类 + 数据时点），不另立格式。
- `-analysis.md` —— 沿用 `football-match-analyzer` manifest 里的 Output Format 表格结构（1X2 / 正确比分 / 亚盘 / 总进球 / 关键洞察 / 推荐），不另立格式。
- `-review.md` —— **本文件定义**，骨架见 Step 2。
- `summary.md` —— 多场汇总表，每行一场，列：场次 / 情报完整度 / 主胜 / 平 / 客胜 / 让球线 / 总进球主线 / 边际价值。单场也写，保持产物一致。

明确写一句：`-intel.md` 与 `-analysis.md` 的格式**以对应 agent manifest 为准**，本文件不复制、不覆盖，避免两处定义漂移。

- [ ] **Step 2: 在文件中给出 `-review.md` 的完整骨架**

```markdown
## 复盘：<主队> vs <客队> | <赛事> | <比赛日>

**结果来源：** WebSearch / 用户提供 —— <来源说明>
**情报完整度（当时）：** 高 / 中 / 低

### 实际结果

| 项 | 值 |
|---|---|
| 最终比分 | X-X |
| 半场比分 | X-X |
| 关键事件 | <红牌 / 伤退 / 点球> |

### 校准指标（1X2）

| 指标 | 模型 | 均匀基线 | 判定 |
|---|---|---|---|
| Brier score | 0.XXX | 0.667 | 优于 / 劣于 |
| Log loss | X.XXX | 1.099 | 优于 / 劣于 |
| 最高概率项命中 | 是 / 否 | — | — |

> Brier score 与 log loss 必须与均匀基线并列展示。脱离基线的绝对值没有意义。

### 其他市场

| 市场 | 预测 | 实际 | 命中 |
|---|---|---|---|
| 正确比分 | 前 10 含 X-X，实际比分概率 X.X% | X-X | 是 / 否 |
| 让球 | <线> 取 <方向> | 赢 / 输 / 走盘 | 是 / 否 |
| 总进球 | <线> 取 大 / 小 | 总进球 X | 是 / 否 |

### 投注方案（若存在 plan.md）

| 注 | 选项 | 赔率 | 命中 | 盈亏 |
|---|---|---|---|---|
| … | … | … | … | … |

**合计：** 投入 X 元，回收 X 元，回收率 X%

### 归因

**这是复盘的核心产出。** 不是复述对错，而是指明哪条情报或哪个建模假设失效：

- [失效点 1] —— 具体到是哪条情报判断错了，或哪个 λ 估计偏了
- [失效点 2]

若预测命中，说明是**因为预想的机制**命中，还是**碰巧**命中。答案对但机制错的，仍然是缺陷。

### 本轮记忆修订

| 记忆条目 | 所属 agent | 改动 | 原因 |
|---|---|---|---|
| <entry-name> | analyzer | n: 2 → 3；置信 降级 | 第三次同向失败 |

若无修订，写「本轮无记忆修订」。

### 样本量声明

n = X。**若 n < 5，本节必须明确写「样本不足，仅作观察」，且本轮不得据以调整任何参数。**
```

- [ ] **Step 3: 验证**

Run:
```bash
f=.claude/skills/football-match-analysis/references/artifact-templates.md
test -f "$f" && echo "exists"
for s in "-intel.md" "-analysis.md" "-review.md" "summary.md" "Brier score" "样本不足，仅作观察"; do
  grep -q -- "$s" "$f" && echo "OK: $s" || echo "MISSING: $s"
done
```
Expected: `exists` 后跟着六个 `OK:`，无 `MISSING:`。

- [ ] **Step 4: 提交**

```bash
git add .claude/skills/football-match-analysis/references/artifact-templates.md
git commit -m "docs(skills): add artifact templates"
```

---

### Task 6: 写 `references/review-protocol.md`

**Files:**
- Create: `.claude/skills/football-match-analysis/references/review-protocol.md`

**Interfaces:**
- Consumes: Task 2 的 reviewer agent、Task 5 的 `-review.md` 骨架
- Produces: 复盘判定与记忆写权限的权威定义，被 SKILL.md 第 0 步引用

- [ ] **Step 1: 写入内容**

须覆盖以下各节，内容以 spec §5.3 为准：

**一、待复盘判定（无状态文件）**

三条全部满足即为待复盘：存在 `<slug>-analysis.md`、目录名日期早于今天、不存在 `<slug>-review.md`。

强调：**文件名就是状态。** 不引入索引文件。删掉 `-review.md` 即让它重回队列 —— 这是刻意设计，便于重跑。

**二、静默规则**

无待复盘项时完全静默。不要输出「已检查，无待复盘项」之类的话 —— 每一步都汇报会让流程变吵，而这一步在多数情况下本来就无事发生。

**三、比赛未结束的处理**

WebSearch 拿不到终场比分 → **不写 `-review.md`、不报错、不重试**。这保证了「没有结果」和「已复盘」不会被混为一谈；否则一次失败抓取会让该场比赛永久退出复盘队列。

**四、校借口径**

- Brier score（多分类，单场）：`BS = Σ_k (p_k − o_k)²`，k ∈ {主胜, 平, 客胜}，取值 0–2，越小越好
- Log loss：`−ln(p_实际结果)`
- **均匀基线**：每项 1/3 时 `BS ≈ 0.667`、`log loss ≈ 1.0986`。**必须与基线并列展示** —— 脱离基线的绝对值没有意义
- 让球与总进球**只记命中/走盘，不算分**，口径简单且不易出错
- 投注方案按**当时实际可得赔率**算盈亏，不按模型的最低可接受赔率

**五、记忆写权限（关键，不可含糊）**

- reviewer 拥有自己的记忆目录：`.claude/agent-memory/football-match-reviewer/`
- reviewer **被显式授权**修订其他 agent 记忆条目中的「证据 / 置信」部分
- **可以**：追加或更新证据标注（n 计数、胜负记录、置信升降级）
- **不可以**：不注明地改写原始论断本身。证据足以推翻论断时，正确做法是**新写一条记忆并以 `[[旧条目名]]` 链接**，保留推理痕迹
- 每次修订必须在 `-review.md` 的「本轮记忆修订」表里留痕

写一句为什么：**假设由 analyzer 持有，证据只能由比赛结果产生。** 不给这条授权，错误假设永远不会被降级，校准闭环就是断的。这正是用户此前手工在做的事（`extreme-mismatch-ucl` 上那条「n=2 均失败，降级为待验证」的标注）。

**六、样本量纪律**

n < 5 时结论一律标注「样本不足，仅作观察」，**不得据以调参**。

- [ ] **Step 2: 验证**

Run:
```bash
f=.claude/skills/football-match-analysis/references/review-protocol.md
test -f "$f" && echo "exists"
for s in "0.667" "log loss" "analysis.md" "review.md" "football-match-reviewer" "样本不足，仅作观察" "不得据以调参"; do
  grep -q -- "$s" "$f" && echo "OK: $s" || echo "MISSING: $s"
done
```
Expected: `exists` 后跟着七个 `OK:`，无 `MISSING:`。

- [ ] **Step 3: 提交**

```bash
git add .claude/skills/football-match-analysis/references/review-protocol.md
git commit -m "docs(skills): add review protocol and memory write permission"
```

---

### Task 7: 同步 `CLAUDE.md`

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: 前六个任务确立的全部结构
- Produces: 仓库文档与现实一致

**背景：** `CLAUDE.md` 目前写的是"三阶段管线 / 三个 agent"，且完全没提 `.claude/skills/`。不改的话，下一个读这份文档的人（或 Claude）会得到过时的地图。

- [ ] **Step 1: 更新 `Repository Structure`**

在 `.claude/agents/` 列表中新增一项：

```markdown
  - `football-match-reviewer.md` — Retrospectively grades frozen predictions against actual results, computes calibration metrics, and amends evidence annotations in other agents' memory.
```

并在列表后新增：

```markdown
- `.claude/skills/football-match-analysis/` — The orchestration skill. `SKILL.md` is the single entry point for the whole pipeline; `references/` holds the stage handoff contracts, the review protocol, and the artifact templates; `scripts/` holds a convenience directory helper.
- `matches/YYYY-MM-DD/` — Runtime output directory (created on demand): per-match `-intel.md`, `-analysis.md`, `-review.md`, plus a `summary.md` and, when a ticket was requested, `plan.md`.
```

- [ ] **Step 2: 更新 `Multi-Agent Workflow`**

把"three-stage pipeline"改为四阶段，并在第 0 步插入复盘：

```markdown
Requests in this domain are handled by a four-stage pipeline, orchestrated by the `football-match-analysis` skill:

0. **Review** — Conditionally, before anything else: launch `football-match-reviewer` for any match under `matches/` that has a `-analysis.md`, a match date earlier than today, and no `-review.md`. If there are none, this step is skipped silently.
1. **Gather** — When the user names a specific match, launch `football-intelligence-gatherer` to collect odds, lineups, form, and H2H data.
2. **Analyze** — Feed the gathered intelligence into `football-match-analyzer` to produce calibrated probabilities and market assessments.
3. **Plan** — If the user wants a lottery ticket, launch `lottery-strategist` using the analyzer's probabilities to generate a ≤20 yuan 竞彩足球 plan. This step requires explicit user consent every time — it spends real money.

Agents should be invoked in order; each stage depends on the previous stage's output file. Prefer invoking the skill rather than dispatching agents ad hoc, so the handoff contracts are respected.

`football-match-reviewer` is the only agent authorized to amend evidence annotations in other agents' memory. It may not silently rewrite a claim — see `references/review-protocol.md`.
```

- [ ] **Step 3: 更新 `Language Conventions`**

在末尾补一句：

```markdown
The reviewer's calibration reports and the skill's orchestration text follow the same rule: match the user's language.
```

- [ ] **Step 4: 验证**

Run:
```bash
grep -n "three-stage\|three stage" CLAUDE.md ; echo "exit=$?"
grep -n "football-match-reviewer" CLAUDE.md | head -5
grep -n ".claude/skills" CLAUDE.md
```
Expected: 第一条无输出（exit=1）；第二、三条各有命中。

- [ ] **Step 5: 提交**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for four-stage pipeline and skills directory"
```

---

### Task 8: 端到端验收

**Files:**
- 无新增（纯验证）

**Interfaces:**
- Consumes: 全部前序任务
- Produces: 对 spec §9 十二条验收标准的逐条核对结论

**说明：** 本仓库无测试框架，这一步是**手动冒烟测试**。第 1–4 项需要真实联网调研，耗时数分钟；第 5–12 项可以用构造的假数据快速验证，不必等真实比赛。

- [ ] **Step 1: 静态完整性检查**

Run:
```bash
echo "== agents ==" && ls .claude/agents/
echo "== skill tree ==" && find .claude/skills -type f | sort
echo "== 硬编码绝对路径残留 ==" ; grep -rn "/Users/" .claude/agents/ .claude/skills/ ; echo "grep-exit=$?"
```
Expected: 4 个 agent；skill 下 5 个文件（SKILL.md + 3 references + 1 script）；绝对路径 grep 无输出。

- [ ] **Step 2: 验证 skill 被 Claude Code 识别**

新开一个 Claude Code 会话（在项目根目录），输入 `/` 后应能在技能列表里看到 `football-match-analysis`。若未出现，检查 frontmatter 的 `name` 是否与目录名完全一致 —— 这是最常见的原因。

- [ ] **Step 3: 用构造数据验证复盘判定（覆盖验收 7/8/9）**

```bash
mkdir -p matches/2026-09-01 matches/2099-01-01
# 待复盘：比赛日已过 + 有 analysis + 无 review
printf '# fake\n' > matches/2026-09-01/fake-vs-team-analysis.md
# 已复盘：不应再触发
printf '# fake\n' > matches/2026-09-01/done-vs-team-analysis.md
printf '# fake\n' > matches/2026-09-01/done-vs-team-review.md
# 未来比赛：不应触发
printf '# fake\n' > matches/2099-01-01/future-vs-team-analysis.md
```
然后在会话中触发 skill（例如说「分析一下某场比赛」），确认：
- 只有 `fake-vs-team` 被当作待复盘（验收 7）
- `done-vs-team` 与 `future-vs-team` 被忽略（验收 8 的静默、验收 9 的未来场次）

**清场：**
```bash
rm -rf matches/2026-09-01 matches/2099-01-01
```

- [ ] **Step 4: 真实单场冒烟测试（覆盖验收 1–6）**

选一场近期已结束的比赛，在会话中说「分析一下 <主队> vs <客队>」。逐条核对：

| # | 标准 | 预期 |
|---|---|---|
| 1 | skill 被触发 | gatherer、analyzer 依次运行 |
| 2 | 第 3 步后停住 | 询问是否出方案；不自动产 `plan.md` |
| 3 | 回答「要」 | strategist 运行，`plan.md` 总额 ≤ 20 元 |
| 6 | 主会话上下文 | 只有路径与摘要，无完整情报原文 |

再给两场比赛（验收 4）：两场并行，产出 4 份文件 + `summary.md`。

再说「只要分析」（验收 5）：流程停在第 3 步。

- [ ] **Step 5: 验证复盘产物格式（覆盖验收 10/11/12）**

对 Step 3/4 中真正跑出 `-review.md` 的那场，人工核对：
- 含 Brier score 与 log loss，且**与均匀基线并列**（验收 10）
- 含归因分析（验收 10）
- 含「本轮记忆修订」清单（验收 10）
- 若修订了 analyzer 记忆，原始论断文字**未被静默改写**（验收 11）
- 若 n < 5，含「样本不足，仅作观察」且未据此调参（验收 12）

- [ ] **Step 6: 提交验收产物**

```bash
git add matches/
git commit -m "test: end-to-end smoke test artifacts for the analysis pipeline"
```

若 Step 3 的构造数据已清理、Step 4 未产生真实产物，则跳过本步并在交付说明中注明。

---

## 交付说明

- 本计划不改动三个现有 agent 的领域指令正文，只按 Task 1 修路径与过时句子。
- `matches/` 下的真实产物默认提交；若你不希望情报/分析入库，在 `.gitignore` 加一行 `matches/` 即可，**但 `-review.md` 建议保留** —— 它是校准闭环的凭据。
- 工作区原有脏改动（`.claude/settings.local.json`、已删除的 `match-analysis-2026-06-26.md`）**不属于本次范围**，所有 `git add` 都用精确路径规避。
