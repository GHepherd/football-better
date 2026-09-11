# 足球比赛分析编排 Skill — 设计文档

**日期：** 2026-09-11
**状态：** 已确认，待实现
**目标仓库：** `/Users/sheoherd/Desktop/f`

---

## 1. 问题

仓库里已有三个成熟的 agent manifest（`.claude/agents/`），它们各自承载了完整的领域知识：

| Agent | 职责 | manifest 大小 |
|---|---|---|
| `football-intelligence-gatherer` | 采集赛前情报（赔率、阵容、近 10 场、H2H） | ~20 KB |
| `football-match-analyzer` | 情报 → 1X2 / 正确比分 / 让球 / 总进球概率 | ~21 KB |
| `lottery-strategist` | 概率 → ≤20 元竞彩足球投注方案 | ~19 KB |

**缺失的是它们之间的两样东西。**

**其一，编排。** 今天三层依赖完全靠 agent `description` 字段里的自然语言暗示（"应该在 gatherer 之后启动"），不存在任何显式的：

- 阶段顺序与交接契约（上一步必须交出什么，下一步才能开工）
- 多场比赛的处理方式（现有 `CLAUDE.md` 只描述单场；但竞彩的混合过关需要 2–4 场组合）
- 涉及真实支出的确认闸门
- 产物落盘规范

结果就是：每次都要靠主会话即兴编排，交接口径不一致，中间产物丢失（`match-analysis-2026-06-26.md` 那份四场合并分析就是一个手工产出的孤儿文件，现已删除）。

**其二，校准闭环。** 现在的流程只预测、不复盘，没有任何机制把"预测 vs 实际"的落差回灌到模型。

这个缺口用户其实已经在手工补了：analyzer 的记忆条目 `extreme-mismatch-ucl` 上挂着「⚠️ 2026-09-09 实战 n=2 均失败，降级为待验证」。这说明**正确的回路是存在的、也是有价值的，只是靠人手维护，所以零散、不可靠、会漏**。本设计把它固化。

## 2. 已确认的决策

| # | 决策 | 选择 |
|---|---|---|
| 1 | Skill 形态 | **1 个编排 skill，复用现有 3 个 agent**（不搬迁、不删除 agent 内容） |
| 2 | 默认流程 | 自动跑完 gather → analyze，**在出体彩方案前硬停一次确认** |
| 3 | 多场支持 | **支持**；skill 负责拼装场次集合 |
| 4 | 产物落盘 | **落盘**到 `matches/YYYY-MM-DD/` |
| 5 | 复盘执行者 | **新增第 4 个 agent `football-match-reviewer`** |
| 6 | 复盘触发判定 | **以文件系统为准**，无额外状态文件 |
| 7 | 实际比分来源 | **WebSearch 为主**（WebFetch 对体育域名被封，见 `webfetch-blocked-sports-domains` 记忆）；用户可直接报比分覆盖 |

## 3. 为什么是"薄 SKILL.md + references/"

Skill 的 `SKILL.md` 每次被触发都会整体进入上下文，因此必须短。三份交接口径只在真正跑到对应步骤时才需要，属于渐进式披露的典型对象。把数据契约单独成文还有一个好处：以后改"情报要交哪些字段"，不必动主流程。

被否决的两个方案：

- **单文件全塞** —— 一次加载约 300 行，流程与契约混在一起，改一处要读全文。
- **skill 自己 fork subagent 跑编排** —— 多一层嵌套，且确认闸门需要与用户对话，fork 后交互要绕回主会话。

## 4. 文件结构

新增部分：

```
.claude/agents/
└── football-match-reviewer.md        # 第 4 个 agent（新）

.claude/skills/football-match-analysis/
├── SKILL.md                          # 入口：触发条件 + 四阶段编排 + 闸门
├── references/
│   ├── handoff-contracts.md          # 阶段间数据契约
│   ├── review-protocol.md            # 复盘协议：待复盘判定、校准指标、记忆写权限
│   └── artifact-templates.md         # 落盘文件骨架
└── scripts/
    └── new-match-dir.sh              # 建 matches/YYYY-MM-DD/ 目录
```

运行时产物目录（不预先创建，由脚本生成）：

```
matches/
└── 2026-09-11/
    ├── arsenal-vs-liverpool-intel.md
    ├── arsenal-vs-liverpool-analysis.md
    ├── arsenal-vs-liverpool-review.md      # ← 复盘产物
    ├── chelsea-vs-spurs-intel.md
    ├── chelsea-vs-spurs-analysis.md
    ├── chelsea-vs-spurs-review.md
    ├── summary.md
    └── plan.md
```

命名规范：slug = `<主队>-vs-<客队>`，全小写、连字符分隔；日期目录用比赛日（不是分析日）。

**路径一律用相对路径书写**（`matches/YYYY-MM-DD/...`、`.claude/agent-memory/...`），落到工具调用时再解析为绝对路径 —— `Write` 工具要求绝对路径。这样 skill 与 manifest 与机器、克隆位置无关。

## 5. 组件设计

### 5.1 `SKILL.md`

Frontmatter：

```yaml
---
name: football-match-analysis
description: 编排足球比赛分析全流程 —— 复盘已出结果的历史预测、采集赛前情报、产出概率分析、生成 ≤20 元竞彩足球投注方案。当用户点名一场或多场比赛（"分析一下阿森纳 vs 利物浦"）、要求出投注方案（"分析这几场，给我个方案"）、或询问该流程本身时使用。
---
```

正文包含五块：

1. **触发与角色** —— 本 skill 是默认入口。明确写死一条：**不要自己重写任何阶段的领域逻辑，一律交给对应 agent**。agent 仍可被单独触发（例如只想补一次情报），两者不互斥。
2. **执行流程** —— 第 6 节的流程图，逐步展开，含每步的 agent 名、输入、产物路径。
3. **闸门规则** —— 第 4 步前的确认规则，以及"用户中途说不买了就停在第 3 步"。
4. **复盘前置规则** —— 何时执行、何时跳过（见 5.3）。
5. **引用指针** —— 何时读 `references/` 下的三份文件。主流程不复制它们的内容。

### 5.2 关键机制：产物走文件，不走上下文

这是本设计的核心，直接决定主会话的上下文开销。

每个阶段 agent **自己把产物写到磁盘**（agent 有 Write 工具），然后只返回一段紧凑回执：产物路径 + 3–5 行要点摘要（含情报完整度 高/中/低、关键风险）。

下一个阶段 agent **从磁盘 Read 上一阶段的文件**，而不是从主会话接收全文。

这样主会话里永远不承载 60 KB 量级的原始情报，只流转路径与摘要。N 场比赛时这一点尤其关键。

### 5.3 复盘机制

#### 5.3.1 待复盘判定（无状态文件）

skill 在每次流程开始时扫 `matches/`，一条比赛满足**全部**三个条件即为待复盘：

1. 存在 `<slug>-analysis.md`（有预测可比对）
2. 比赛日 **早于今天**（`matches/` 的日期目录名即比赛日）
3. 不存在 `<slug>-review.md`（尚未复盘）

文件名就是状态：不需要额外的索引文件，不会与实际产物漂移，删掉 `-review.md` 即可让它重回待复盘队列。

**执行规则：**

- 有 N 条待复盘 → 派 `football-match-reviewer` 处理
- 一条都没有 → **静默跳过**，不打断、不提示，直接进新分析
- 用户说"这次别复盘" → 跳过，且**不写** `-review.md`，下次仍会提醒
- 比赛尚未结束（WebSearch 显示未终场或查不到结果）→ **不写** `-review.md` 且**不报错**，留给下次。这保证"没有结果"和"已复盘"不会被混为一谈

#### 5.3.2 复盘做什么

`football-match-reviewer` 的完整协议放在 `references/review-protocol.md`，manifest 引用它。要点：

**输入**：`<slug>-analysis.md`（预测，已冻结在磁盘上，不可篡改）+ WebSearch 取回的实际结果。

**步骤：**

1. 提取预测：1X2 概率、正确比分前 10、让球线、总进球线、当时的推荐（若有）
2. 取实际结果：最终比分、半场比分、关键事件（红牌、伤退、点球）；标注来源与置信
3. 计算校准指标：
   - **1X2**：Brier score 与 log loss；预测最高概率项是否命中
   - **正确比分**：实际比分是否落在前 10 表内；模型当时给它多少概率
   - **让球**：方向是否命中，是否走盘
   - **总进球**：over/under 是否命中
   - **投注方案**（若存在 `plan.md`）：每注是否命中、按当时赔率的盈亏、20 元本金回收率
4. **归因** —— 这是复盘真正的价值所在，不能只报对错：哪条情报或哪个假设错了（伤停判断、轮换预期、动机、市场定价、联赛特性）
5. 写 `<slug>-review.md`
6. 回写记忆（见 5.3.3）

**度量口径统一**：Brier score 与 log loss 只在 1X2 上算（三项归一，口径稳定）；让球与总进球只记命中与否，不强行算分数。n 很小时（n<5）结论一律标注为「样本不足，仅作观察」，不得据此调参。

#### 5.3.3 记忆写权限

这是本设计需要明确的一处所有权问题，不能含糊。

现状：**假设由 analyzer 持有，证据由实战产生。** analyzer 记忆里写的是"XX 情形下小球常被高估"这类**假设**；而验证它的**证据**只存在于比赛结果里。

规则：

- `football-match-reviewer` **拥有自己的记忆目录**，用于沉淀校准方法层面的教训（例如"我的 Brier 在悬殊对阵上系统性偏差"）。
- 关键的是，reviewer 被**显式授权修订其他 agent 记忆条目中的「证据/置信」部分** —— 这正是用户今天在手工做的事（给 `extreme-mismatch-ucl` 加「n=2 均失败，降级为待验证」）。授权范围严格限定为：
  - **可以**：追加或更新证据标注（n 计数、胜负记录、置信升降级）
  - **不可以**：在不注明的情况下改写原始论断本身。若证据已足以推翻论断，正确做法是**新写一条记忆并链接旧条目**（`[[旧条目名]]`），保留推理痕迹
- 每次修订都必须在 `<slug>-review.md` 里留下「本轮修订了哪些记忆、为什么」的清单，保证可追溯。

不给这条授权的话，analyzer 记忆里那些错误假设永远不会被降级 —— 校准闭环就是断的。

### 5.4 第 4 个 agent：`football-match-reviewer`

Frontmatter：

```yaml
---
name: football-match-reviewer
description: 复盘已结束比赛的历史预测，做校准评估并把教训回写记忆。当用户说"复盘/上次那几场结果如何/准不准"，或 skill 检测到 matches/ 下存在已出结果但未复盘的比赛时使用。
model: inherit
color: yellow
memory: project
---
```

正文结构与现有三个 agent 保持一致（领域指令 + 输出格式 + memory 规则）。

**新 manifest 不复用那段通用 memory 样板**（三个老 manifest 里逐字重复、各占约 130 行），而是写一段针对复盘的记忆指引：记什么（校准方法层面的系统性偏差）、不记什么（单场对错本身，那属于 `-review.md` 产物而非记忆）。

**三个老 manifest 只做最小改动** —— 仅按 7(a) 修路径与过时句子，不重写它们的记忆样板。理由：那 130 行虽然重复，但当前工作正常；在本次改动里顺手重写三份会让 diff 膨胀到难以审阅，与本次目标无关。

### 5.5 `references/handoff-contracts.md`

把今天隐式的"agent 输出格式"变成显式契约。

**gatherer → analyzer**

必填字段：

- 两队近 10 场（比分、对手、主客场分离）
- H2H（近 5–10 次交锋）
- 赔率：欧赔 1X2 与亚盘让球，注明采集时点
- 阵容 / 伤停：确认首发或预测首发，逐项标注

每个数据点必须带 `CONFIRMED` / `REPORTED` / `PREDICTED` 标记（agent 现有规范已要求）。

缺项处理：analyzer **必须**在报告开头显式列出「因缺 X，以下概率不可信」，而不是静默补全。

**analyzer → strategist**

必填字段：

- 每场的 1X2 / 正确比分（前 10）/ 让球 / 总进球概率表
- 每场一个「情报完整度：高/中/低」
- 每场一个「是否有边际价值」结论

缺项处理：情报完整度为「低」时，strategist 必须降级为保守方案或明确建议观望；不得基于低完整度数据出激进过关。

**analyzer → reviewer**

reviewer 直接 Read `-analysis.md` 原始文件，不走主会话转述。契约即 5.3.2 列出的五项必填字段；缺项时 reviewer 在报告中标注「该市场本轮无法评估」，不得跳过整个复盘。

### 5.6 `references/artifact-templates.md`

四类文件的骨架：

- `*-intel.md` —— 沿用 gatherer 现有 Output Format 的四个分类 + 数据时点
- `*-analysis.md` —— 沿用 analyzer 现有 Output Format 的表格结构（1X2 / 正确比分 / 亚盘 / 总进球 / 关键洞察 / 推荐）
- `*-review.md` —— 校准表 + 归因 + 记忆修订清单
- `summary.md` —— 多场汇总成一张表，供 strategist 一次性读取

### 5.7 `scripts/new-match-dir.sh`

幂等地创建 `matches/YYYY-MM-DD/`。纯便利脚本，失败不阻塞流程（主会话可直接 Write，Write 会自建目录）。

## 6. 执行流程

```
[0] 复盘前置检查（条件执行）
     │   扫 matches/：有 -analysis.md、比赛日 < 今天、无 -review.md
     │   有 → football-match-reviewer（可并行，每场独立）
     │   无 → 静默跳过
     ↓
[1] 确认场次清单（新分析）
     │   单场：从用户话里直接取
     │   多场：列出理解的清单，请用户确认或增删
     ↓
[2] football-intelligence-gatherer  × N 场
     │   同一条消息里并行 dispatch
     │   各自写 matches/<date>/<slug>-intel.md，回执只带路径 + 摘要
     ↓
[3] football-match-analyzer  × N 场
     │   各自 Read 对应 -intel.md 后写 <slug>-analysis.md
     │   全部完成后主会话写 summary.md
     ↓
   ⏸ 闸门：询问是否出体彩方案
     │   硬停。用户没明确说要，绝不进第 4 步。
     │   用户说"只要分析"→ 到此结束。
     ↓
[4] lottery-strategist  × 1
          Read summary.md → 写 plan.md
```

闸门守则（写进 `SKILL.md`）：

- 第 4 步涉及真实支出，属不可逆操作，每次都要显式征求同意 —— 上一轮的同意不延续到下一轮
- 第 0、2、3 步是纯信息工作，不打断；第 0 步在无待复盘项时完全静默
- 用户随时可说"停"，停在哪一步就是哪一步

## 7. 附带修复

两处现有问题会影响本 skill 的编排成立，一并修：

**(a) 三个 agent 的记忆路径失效且不可移植。** 三份 manifest 都写死 `/Users/sheoherd/Desktop/football/.claude/agent-memory/<agent>/` —— 仓库实际在 `/Users/sheoherd/Desktop/f/`，且换机器/换克隆位置必然失效。三份末尾还都写着「Your MEMORY.md is currently empty」，而实际 `MEMORY.md` 早已有内容。

改法：路径改为**相对项目根目录**的 `.claude/agent-memory/<agent>/`。注意 `Write` 工具要求绝对路径，所以 manifest 措辞应写成「写入相对当前工作目录的 `.claude/agent-memory/<agent>/`；调用 Write 前先解析为绝对路径」，既保证可移植又不违反工具约束。同时删掉过时的「currently empty」句。

**(b) `matches/` 的版本控制策略。** 仓库当前没有 `.gitignore`，因此 `matches/` 默认会被提交。**默认选择：全部提交。** 理由：情报、分析、复盘都是当时快照，留痕正是校准闭环的凭据 —— 尤其 `-review.md` 就是证据本身，不入库则闭环不可追溯。若日后想忽略，加一行 `matches/` 到 `.gitignore` 即可 —— 本设计不预先创建 `.gitignore`。

**(c) `CLAUDE.md` 同步。** 该文件目前描述的是"三阶段管线"与"三个 agent"，新增 reviewer 后需更新为四阶段，并在"Repository Structure"里补上 `.claude/skills/`。

## 8. 非目标

- 不搬迁、不改写三个现有 agent 的领域内容（保留其独立 memory 机制）
- 不删除 agent，agent 仍可被单独直接触发
- 不引入自动化数据抓取脚本（情报与比分采集仍由 agent 用其现有工具完成）
- 不做跨赛季/跨联赛的统计建模与回测平台 —— 复盘只到"逐场校准 + 记忆修订"这一层

## 9. 验收标准

**编排**

1. 新会话中说「分析一下本周六阿森纳 vs 利物浦」，`football-match-analysis` 被触发，gatherer 与 analyzer 依次运行，`matches/<date>/` 下出现 `-intel.md` 与 `-analysis.md`
2. 第 3 步结束后流程停住并询问是否出方案；用户不回答时不会自动产出 `plan.md`
3. 用户回答「要」，strategist 被触发并写出 `plan.md`，总额 ≤ 20 元
4. 一次性给两场比赛，两场的情报采集并行发生，产出 4 份文件 + 1 份 `summary.md`
5. 用户说「只要分析」，流程停在第 3 步，不产生 `plan.md`
6. 主会话上下文中不出现完整情报原文（只有路径与摘要）

**复盘**

7. 存在一场比赛日早于今天、有 `-analysis.md` 但无 `-review.md` 的比赛时，流程先派 reviewer，产出 `-review.md` 后再进入新分析
8. 无任何待复盘比赛时，流程**完全静默**地直接进入新分析，不产生任何输出或提示
9. 一场尚未结束的比赛（WebSearch 查不到终场比分）不会被写成 `-review.md`，下次仍会被识别为待复盘，且流程不报错
10. 复盘报告含 1X2 的 Brier score 与 log loss、各市场命中情况、归因分析、以及「本轮修订了哪些记忆」清单
11. reviewer 对一个已存在的 analyzer 记忆条目追加了证据标注；原始论断文字未被静默改写
12. 样本量 n<5 时，结论明确标注「样本不足，仅作观察」
