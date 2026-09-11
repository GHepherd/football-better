---
name: webfetch-blocked-sports-domains
description: WebFetch is blocked for many football data domains (sportsmole, managingmadrid, legalbet); WebSearch summaries are the reliable fallback for match intel
metadata:
  type: reference
---

WebFetch fails with "Unable to verify if domain is safe to fetch" for sportsmole.co.uk, managingmadrid.com, legalbet.uk and other football betting/news domains. As of 2026-09-08 the block appears total — even espn.com, en.wikipedia.org, uefa.com and whoscored.com fail with the same error.

**Why:** Network/enterprise security policy blocks claude.ai from verifying these domains.

**How to apply:** For pre-match intelligence gathering, rely on WebSearch with specific queries (injuries, lineups, results by date, odds, H2H) — the search summaries return rich structured detail. Don't waste calls attempting WebFetch on betting/news domains; go straight to multiple targeted WebSearch rounds (5-7 queries typically covers odds, lineups, injuries, form, H2H).
