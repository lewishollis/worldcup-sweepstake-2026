# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

**Run the app locally:**
```bash
bin/dev   # starts Rails + Tailwind watcher (Procfile.dev)
```

**Run all tests:**
```bash
bin/rails test
```

**Run a single test file:**
```bash
bin/rails test test/services/group_qualification_test.rb
```

**Run a single test by line number:**
```bash
bin/rails test test/services/group_qualification_test.rb:42
```

**Sync match data from BBC (locally, instead of Heroku Scheduler):**
```bash
bin/rails matches:sync
```

**Refresh AI insight cache:**
```bash
bin/rails ben_botcurdy:refresh
```

**Simulate a full tournament end-to-end (destroys all match data):**
```bash
bin/rails tournament:simulate
```

**Seed the database:**
```bash
bin/rails db:seed
```

## Known pre-existing test failures

`bin/rails test` reports **3 failures on a clean `main`** that are not regressions:

1. `test/services/ben_motson_service_test.rb` — two `:leaderboard` tests. They call `BenBotcurdyService.new(:leaderboard).generate_insight` which returns `nil` early because `tournament_status == :not_started` in the fixture setup.
2. `test/tasks/tournament_simulate_test.rb:162` — asserts 88 total matches but the simulation now produces 104. A stale count expectation.

A clean run should show **exactly these 3 failures**. Any others are regressions.

## Architecture

This is a **Rails 7.1 / PostgreSQL / Hotwire** app for a 12-person World Cup 2026 sweepstake. Each friend owns a group of 4 national teams drawn from the actual 2026 bracket. Friends score points as their teams progress through knockouts.

### Scoring model

Points are computed live from match results, never stored on teams or groups:
- `Team#progression_score` — `+1` for reaching the main knockout bracket (Last 32 or better), then `+1` per knockout win, `+0.5` for the 3rd-place final win.
- `Group#total_points` — sums `progression_score` across all teams in the group.
- "Qualifying" (`+1`) is awarded the moment it's mathematically certain (see `KnockoutQualification`) or a knockout fixture exists — not when the BBC feed eventually publishes it.

### Match data pipeline

Matches are fetched from **BBC Sport's internal scores-fixtures API** on every `MatchesController#index` request (live data), and also by the `matches:sync` Rake task (run every few minutes by Heroku Scheduler in production).

The BBC feed has known quirks handled by `BbcEventParser`:
- Feed may leave `status: PreEvent` even after kick-off; unconfirmed scores (`scoreUnconfirmed`) signal the match is live.
- Stale payloads can arrive out of order — `BbcEventParser.merge_status` never lets a stale payload regress a match from `MidEvent` back to `PreEvent`.
- `BbcEventParser.presumed_live?` treats a match as live for 3 hours after kick-off even if the feed hasn't caught up.

Team names in the BBC feed differ from seeds (`"United States"` → `"USA"` etc.) — `Team.canonical_name` / `Team::BBC_NAME_ALIASES` handles this mapping.

### Qualification pipeline (group stage)

`GroupTable` — computes live standings from persisted `Match` rows (PostEvent only).

`GroupQualification` — pure mathematical oracle. Enumerates all possible completions of remaining group fixtures and classifies each team as `:clinched_top2`, `:cannot_finish_top2`, or `:in_contention`. Conservative: a points-tie at the top-2 boundary is "not safe". Does NOT reason about goal difference tiebreaks.

`KnockoutQualification` — class-level memoized cache of teams that have clinched top 2. Invalidated by `GameStateSnapshot.data_version` (a hash of group-stage results), so it recomputes when results change.

`QualificationStatus` — presentation-layer wrapper that maps the oracle + live table position to one of `:through`, `:likely`, `:contention`, `:third_hope`, `:out` for display. "Likely" requires a points lead over the first non-qualifying team (not just goal-difference lead).

### Scenario engine

`ScenarioEngine` — given a single match, computes what each outcome (home win / draw / away win) would do to every friend's score and leaderboard rank. Used on `matches/show` (PreEvent matches) and in AI prompts.

`TournamentContextService#pivotal_matches` — ranks upcoming matches by maximum possible rank change across all friends, returning the top 3.

### AI commentary

`BenBotcurdyService` — Gary Lineker persona. Builds a structured world-state prompt from `TournamentContextService` and `ScenarioEngine`, then calls Groq (primary) → Claude Haiku (fallback) → static string.

`GroqClient` — direct `Net::HTTP` call to Groq's OpenAI-compatible endpoint. Primary model: `openai/gpt-oss-120b`; fallback: `llama-3.3-70b-versatile`. Timeouts are deliberately tight (5s connect, 15s read) to avoid Heroku H12s.

`AiInsightCache` — DB-backed cache keyed by a version hash of current standings + tournament status. Commentary is regenerated automatically when the leaderboard changes.

`GameStateSnapshot` — single source of factual context for all AI services. Assembles group tables, qualification flags, team ownership, and per-match qualification effects so AI prompts never hand-assemble world state.

The leaderboard and per-friend AI insights are currently **disabled in the controllers** (commented out) while the daily summary is refined. The `UpcomingMatchesInsightService` on the upcoming matches tab is active.

### Penalty shootout mini-game

Route: `GET /game` → `GamesController#index`. Players tap a penalty target, earn streak points, and scores are stored in `GameScore`. `GameScore.best_per_friend` is used as a tiebreaker on the main leaderboard (when friends are level on sweepstake points). The game UI is a Stimulus controller (`penalty_game_controller.js`).

### Data model relationships

```
Friend — has one Group (sweepstake group)
Group  — HABTM Teams (4 teams per group)
Team   — has many Matches (via home_team_id / away_team_id)
Match  — belongs_to home_team, away_team (both Team)
         stage: "Group Stage" | "Last 32" | "Last 16" | "Quarter-finals" |
                "Semi-finals" | "3rd Place Final" | "Final"
         status: "PreEvent" | "MidEvent" | "PostEvent"
```

`FriendsGroup` and `FriendGroupTeam` are legacy join models; the active sweepstake uses `Group` + `groups_teams`.

### CSS

Tailwind CSS (via `tailwindcss-rails`) is the primary styling layer. Per-component overrides live in `app/assets/tailwind/components/`. DartSass processes `application.scss` for any legacy SCSS. Both watchers run in `bin/dev`.

### Environment variables

- `GROQ_API_KEY` — AI commentary (primary)
- `ANTHROPIC_API_KEY` — AI commentary (fallback to Claude Haiku)
- `ADMIN_PASSWORD` — HTTP basic auth on admin actions (default: `"onlymesucker!"`)
