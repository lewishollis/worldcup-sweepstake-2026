# Upcoming Matches Insight — Design Spec
_2026-05-23_

## Overview

Add AI-generated commentary to the upcoming matches page:
1. A top summary covering the day's matches and leaderboard stakes
2. A per-match one-liner on each match card (favourites for group stage; sweepstake implications for knockouts)

Both are generated in a single Groq API call via a new `UpcomingMatchesInsightService`.

## Architecture

### New Service: `UpcomingMatchesInsightService`

Single responsibility: given a list of upcoming (`PreEvent`) matches, return a structured hash:

```ruby
{
  summary: "Two-three sentence overview of today's matches...",
  per_match: {
    "match_id_1" => "One-liner for this match",
    "match_id_2" => "One-liner for this match"
  }
}
```

**Prompt construction:**
- System prompt: Ben Motson persona + current leaderboard standings
- User message: list of matches, each with:
  - Home team name + sweepstake owner name
  - Away team name + sweepstake owner name
  - Stage
  - For knockout stages only: ScenarioEngine output (friend deltas, rank changes, new leader per outcome)
  - For group stage: no scenario data — ask for general football commentary (favourites, form)
- Instructs Groq to respond in JSON format: `{ "summary": "...", "matches": { "<match_id>": "..." } }`

**Response handling:**
- Parse JSON from Groq response
- Return structured hash
- On parse failure or Groq error: return `{ summary: nil, per_match: {} }` — page degrades gracefully

**Caching:**
- Uses existing `AiInsightCache` model
- Cache key: `"upcoming_matches_insight"` with version = SHA256 of sorted match IDs + current leaderboard state (same approach as `BenMotsonService#leaderboard_cache_version`)
- Invalidates automatically when leaderboard points change or match list changes

### Controller changes: `matches#index`

After filtering to `PreEvent` matches, if any exist:
```ruby
result = UpcomingMatchesInsightService.call(@matches)
@upcoming_summary = result[:summary]
@match_insights = result[:per_match]  # hash of match_id => string
```

`@match_insights` defaults to `{}` so the view never raises on a missing key.

### View changes: `matches/index.html.erb`

**Top summary box** — rendered above the match list when `@upcoming_summary` is present, using the existing `commentary-box` CSS class (same style as current Ben Motson section):

```
[ microphone icon ] Ben Motson's Preview
"Today's matches text..."
```

**Per-match inline text** — rendered below the VS line on each match card when `@match_insights[match.match_id]` is present:

```
Mexico vs South Africa
[Sam]              [Ella]
         VS
  "Mexico are slight favourites but Ella's South Africa could spring a surprise..."
```

Small, italic, muted text — does not disrupt the existing card layout.

## Caching Strategy

| Scenario | Behaviour |
|---|---|
| Same matches, same leaderboard | Served from `AiInsightCache` — no Groq call |
| New match added / match completed | Cache miss → new Groq call |
| Leaderboard points change | Cache miss → new Groq call |
| Groq fails | Return empty hash, no cache write, page shows no commentary |

## WhatsApp Reuse

`UpcomingMatchesInsightService.call(matches)` returns a plain Ruby hash. The future WhatsApp morning digest job will:
1. Fetch today's upcoming matches
2. Call the same service
3. Format `summary` + `per_match` values into a WhatsApp message string

No changes to the service needed at that point.

## Out of Scope

- WhatsApp sending (separate task)
- Live / finished match commentary (existing `BenMotsonService` handles those)
- Per-match show page (already handled by `MatchInsightService`)
