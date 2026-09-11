---
name: sourcing-football-results
description: 如何可靠取得足球终场比分——WebFetch 对体育域名全阻，WebSearch 可用且能交叉验证
metadata:
  type: reference
---

**WebFetch 对足球数据域名基本全阻**（sportsmole、espn、uefa.com、whoscored 等均返回 "Unable to verify if domain is safe to fetch"）。不要把调用预算浪费在 WebFetch 上。

**WebSearch 可用，且足以交叉验证。** 有效做法：用两个不同角度的 query 各搜一次（一个按「对阵 + 日期 + 赛事」，一个按「比分 + 进球者」），比对结果。当多个独立来源在比分、半场比分、进球者与进球时间上一致时，置信度可判为「高」。

**Why:** 2026-09-11 复盘阿森纳vs切尔西（2026-09-06）时，WebFetch 全线失败，但 WebSearch 返回了 UEFA/FIFA Match Centre、OneFootball、beIN Sports、Yahoo Sports、Sky Sports、TSN、ESPN 等来源，比分与进球时间线完全一致，无需任何单源信任。

**How to apply:** 每场复盘先跑两次 WebSearch（角度见上），再决定是否有可靠终场比分。**一个陷阱：** 同对阵的历史交锋也会出现在结果里（如 2026-03 的阿森纳 2-1 切尔西与 2026-09 的同比分），须用日期与进球者交叉排除，否则会把旧赛果当成新赛果。若两个角度都拿不到终场比分，按协议不写 review、不重试、留待下次判定。

相关：[[review-artifact-provenance]]
