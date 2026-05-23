# AI Bot Enhancement Design

**Date:** 2026-05-23
**Status:** Approved

## Overview

Enhance the existing AI bot to understand teams, the sweepstake scoring structure, and the full tournament schedule. The bot must model and forecast outcomes and provide insights like "If Brazil beat France tonight, Lewis gets 4 points and leads." Initial delivery targets the web interface only; WhatsApp integration to follow later.

## Approach: Math-First, AI-Last

The core principle: Ruby computes all sweepstake maths deterministically. The AI only narrates pre-computed facts. This guarantees accuracy — the AI never calculates, only writes.

---

## Section 1: Data Layer

### 1a. Existing match data (no change required)
Group standings are computed on the fly from existing `Match` records — wins, draws, losses, goal difference, points per team. No new API or table needed.

### 1b. BBC Sport RSS feed (new)
- Source: `https://feeds.bbci.co.uk/sport/football/rss.xml`
- Fetched **twice daily**: 7am (pre-match day context) and 10pm (post-match reaction)
- Stored in a new `NewsItem` table: `title`, `summary`, `published_at`, `guid` (unique, for deduplication)
- Top 5 most recent items injected into every AI prompt as "latest tournament context"
- Fetched via a Rake task triggered by the existing `whenever` cron scheduler

### 1c. Sweepstake state (existing, used more fully)
Friends, groups, multipliers, team ownership, and current points are already in the DB. These are passed completely to the ScenarioEngine and AI prompts.

---

## Section 2: ScenarioEngine

A pure Ruby service. Takes an upcoming match, returns exact sweepstake consequences for every possible outcome. No AI involved.

### Inputs
- The match (home team, away team, stage)
- Current friend/group/team/points state from DB

### Scoring model (canonical definition)

Three distinct concepts, kept separate throughout:

**1. Team tournament points** — points a team earns through the tournament:
```
Group Stage progression (entering knockout):  +1 pt
Last 16 win:                                  +1 pt
Quarter-final win:                            +1 pt
Semi-final win:                               +1 pt
Final winner:                                 +2 pts
Final runner-up:                              +1 pt
3rd Place Final win:                          +1 pt
```

**2. Friend score** — derived from team points, never stored independently:
```
friend.score = friend.groups.sum { |g| g.teams.sum(&:points) * g.multiplier }
```
Multipliers are per-group (2x–6x), set at sweepstake draw time.

**3. Leaderboard rank** — friends ordered by `friend.score` descending. Ties broken by earliest points achieved (existing behaviour).

### Outputs

For each scenario (home win / draw / away win; or home/away only for knockouts), the engine returns three distinct objects:

```ruby
{
  home_win: {
    # 1. Team tournament points awarded in this scenario
    team_points: [
      { team: "Brazil", points_awarded: 1, reason: "Last 16 win" }
    ],

    # 2. Friend score deltas (computed from team_points × multiplier)
    friend_deltas: [
      { friend: "Lewis", delta: 3, new_total: 18 }
    ],

    # 3. Leaderboard rank changes
    rank_changes: [
      { friend: "Lewis", old_rank: 2, new_rank: 1 },
      { friend: "Sarah", old_rank: 1, new_rank: 2 }
    ],

    new_leader: "Lewis"
  },
  draw: { ... },
  away_win: { ... }
}
```

---

## Section 3: AI Layer (Groq)

### Model
- **Primary**: `llama-4-scout` on Groq ($0.11/$0.34 per million tokens)
- **Fallback**: `llama-3.3-70b-versatile` if Scout fails
- Replaces all existing Anthropic API calls

### GroqClient
A single `GroqClient` service class wraps the Groq API. Replaces the existing Anthropic client usage across `BenMotsonService`, `AiCommentaryService`, and `AiLeaderboardInsightsService`. Standard interface: takes a system prompt + user message, returns string response.

### Prompt types

**Prompt constraints (both types)**
- The model must only paraphrase the structured facts it receives — it must never invent alternative outcomes, scores, or standings
- Each scenario must be kept to 1-2 sharp sentences; no padding or waffle
- The system prompt explicitly states: "You are given pre-computed facts. Report them faithfully in Ben Motson's voice. Do not speculate beyond what is provided."

**Match-level insight prompt**
- System context: Ben Motson persona, sweepstake scoring rules summary, current leaderboard, **2-3 most recent football-relevant news items**
- User message: ScenarioEngine output for this match (all three objects: team_points, friend_deltas, rank_changes)
- Output: 1-2 sentences per scenario in Ben Motson's voice
- Example: *"If Brazil pip France tonight, Lewis rockets to the top with 18 points — and with Argentina still to play, he could run away with this."*
- Football relevance filter: news items included only if they mention either team in the match, or tournament-wide news (injuries, suspensions, group table implications)

**Leaderboard-level insight prompt**
- System context: Ben Motson persona, full standings, all upcoming matches this week with ScenarioEngine output for each, **up to 5 football-relevant news items**
- Output: Short "state of play" paragraph (3-4 sentences max) + 2-3 most pivotal matches (those with the largest possible rank changes)
- Football relevance filter: prefer news about teams still active in the tournament

### Caching
- **Match-level**: New `scenario_insight` (text) and `scenario_insight_cache_key` (string) columns on the `Match` table. Cache key is a SHA256 digest of `match.status` + the serialised points totals of all friends who own either team. Regenerated when key changes.
- **Leaderboard-level**: New `AiInsightCache` model (`key` string, `content` text, `cache_version` string, `generated_at` datetime). Leaderboard insight stored under key `"leaderboard_battleground"`. Cache version is a SHA256 of all current friend points totals. Regenerated when version changes.
- On cache miss: generate synchronously, store, return. Pages show a brief "Analysing..." state.
- On Groq failure: fall back to existing static message templates (existing pattern in BenMotsonService).

---

## Section 4: UI

### Match pages (`/matches/:id`)
- Upcoming matches: insight panel showing all scenarios as compact cards (home win / draw / away win), each with exact points impact + leaderboard shift + Ben Motson commentary
- Finished matches: post-match insight ("As it stands after Brazil's win, Lewis leads by 3...")
- Live matches: current-score implication shown on refresh
- Loading state: subtle "Analysing..." indicator while generating; insight fades in on completion
- Graceful fallback to static message if Groq unavailable

### Leaderboard page (`/leaderboard`)
- "This Week's Battleground" panel at top: 2-3 most pivotal upcoming matches + state-of-play paragraph
- Each friend row: expandable "Your best case this week: +6 points if X and Y both win"

### Constraints
- No new pages — insights slot into existing layouts as panels
- Tailwind styling follows existing patterns
- Mobile-first (existing app is responsive)

---

## Phased Delivery

Ship in four phases to keep debugging tractable:

**Phase 1 — Deterministic engine + static templates**
Build `ScenarioEngine`, `TournamentContextService` (standings only, no news), and wire the output into static insight panels on the match and leaderboard pages. Verify maths is correct end-to-end before any AI is involved.

**Phase 2 — Groq commentary**
Add `GroqClient`, update `BenMotsonService` and `AiLeaderboardInsightsService` to narrate ScenarioEngine output. No news context yet — just structured facts → natural language.

**Phase 3 — News context enrichment**
Add `NewsItem` table, BBC RSS rake task, cron schedule, and football relevance filtering. Inject news into existing prompts.

**Phase 4 — Caching optimisations**
Add `scenario_insight` columns to `Match`, add `AiInsightCache` model, implement cache key/invalidation logic. Until then, generate on every page load (acceptable for low traffic during tournament).

---

## Out of Scope (this iteration)
- WhatsApp delivery (designed for later)
- User-initiated chat / Q&A bot
- Admin news override field
- Approach C caching (background pre-computation) — can be added as optimisation later

---

## New Files / Changes Summary

| File | Action |
|------|--------|
| `app/services/groq_client.rb` | New — Groq API wrapper |
| `app/services/scenario_engine.rb` | New — deterministic sweepstake maths |
| `app/services/tournament_context_service.rb` | New — assembles standings + news for prompts |
| `app/services/ben_motson_service.rb` | Modify — use GroqClient, richer prompts |
| `app/services/ai_commentary_service.rb` | Modify — use GroqClient |
| `app/services/ai_leaderboard_insights_service.rb` | Modify — use ScenarioEngine + GroqClient |
| `app/models/news_item.rb` | New — RSS headline storage |
| `app/models/ai_insight_cache.rb` | New — leaderboard insight cache |
| `db/migrate/..._create_news_items.rb` | New — migration |
| `db/migrate/..._create_ai_insight_caches.rb` | New — migration |
| `db/migrate/..._add_scenario_insight_to_matches.rb` | New — adds scenario_insight + scenario_insight_cache_key to matches |
| `lib/tasks/news_feed.rake` | New — BBC RSS fetch task |
| `config/schedule.rb` | Modify — add 7am/10pm news fetch cron |
| `app/views/matches/show.html.erb` | Modify — add scenario insight panel |
| `app/views/leaderboard/index.html.erb` | Modify — add battleground panel |
