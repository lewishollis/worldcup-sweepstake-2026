# "Already Played" Heads-Up in John Botson's Preview — Design Spec
_2026-06-12_

## Problem

`MatchesController#index` filters `@matches` down to `PreEvent` only before calling
`UpcomingMatchesInsightService.call(@matches)` (see `app/controllers/matches_controller.rb:100`).
The insight service therefore never sees matches that have already kicked off or finished —
even ones that happened just hours earlier on the same UK day.

Because World Cup fixtures span time zones, a match can finish in the early hours of the UK
day while another match for the same "next match day" doesn't kick off until that evening.
Right now, John Botson's preview only talks about the evening fixture and gives zero
acknowledgement that an earlier match has already been and gone — even though friends might
want a heads-up to go watch the highlights.

## Goal

When generating John Botson's preview for the next match day, also acknowledge any matches
that finished recently (overnight or earlier today) — **without revealing scores, goalscorers,
winners, or results** — so the message stays shareable even after some of today's action has
already happened.

## Architecture

### 1. New data source: `recently_finished_matches`

A new private method on `UpcomingMatchesInsightService` queries the `Match` table directly.
This mirrors the existing pattern in `TournamentContextService`, which also queries `Match`
directly rather than relying on what the controller passed in. No controller changes are
needed — matches are already persisted via the BBC sync in `MatchesController#index` regardless
of the current tab's filter.

```ruby
def recently_finished_matches
  Match.where(status: "PostEvent")
       .where(start_time: 24.hours.ago..Time.current)
       .includes(:home_team, :away_team)
       .order(:start_time)
end
```

**Window:** a rolling 24 hours from `Time.current`. This naturally covers "overnight" matches
that finished in the small hours of the UK day while the next preview covers an evening
kickoff the same day — without needing fragile UK-calendar-date-boundary logic (which is the
root cause of the current gap).

**Scope:** `PostEvent` (finished) matches only. `MidEvent` (currently live) matches are out of
scope — the Live tab already surfaces those.

### 2. Prompt changes

**`build_user_message`** — if `recently_finished_matches` is non-empty, prepend a new section
before the "MATCHES ON ..." section:

```
MATCHES ALREADY PLAYED (DO NOT REVEAL RESULTS):
- Korea Republic vs Czechia — Group Stage — Thursday 12 June 2026, 02:00 UK time
```

Only team names, stage, and kickoff time are included — no scores, no sweepstake owners. This
keeps the data given to the model minimal and avoids indirect leaks via standings (see Out of
Scope below for the knockout-stage caveat).

If `recently_finished_matches` is empty, the section is omitted entirely — existing behaviour
and tests for the "MATCHES ON ..." section are unchanged.

**`build_system_prompt`** — add a new rule:

> "If any matches are listed under MATCHES ALREADY PLAYED, open with one brief sentence
> acknowledging they've happened and pointing people to the highlights. Never mention the
> score, goalscorers, winner, or result of these matches under any circumstances."

This sits alongside the existing accuracy rules ("never invent scores...", "ONLY discuss the
matches listed...") without weakening them.

### 3. Caching

`cache_version` currently hashes `PERSONA_VERSION`, today's date, the `@matches` IDs, the
leaderboard state, and tournament status. Add the sorted IDs of `recently_finished_matches` to
that hash:

```ruby
recent_ids = recently_finished_matches.map(&:match_id).sort.join(",")
```

This means:
- As soon as a match transitions to `PostEvent` and enters the 24h window, the cache
  regenerates and the heads-up appears.
- ~24h later, once that match falls out of the window, the cache regenerates again and the
  heads-up disappears automatically — no manual cleanup needed.

## Testing

- New test: with a `PostEvent` match whose `start_time` is within the last 24h,
  `build_user_message` includes the "MATCHES ALREADY PLAYED" section with team names, stage,
  and kickoff time — and does **not** include the score.
- New test: `build_system_prompt` includes the no-spoiler rule.
- New test: `cache_version` changes when the set of recently-finished matches changes (a match
  enters/exits the 24h window).
- Existing tests (no recently-finished matches in the fixture data) continue to pass unchanged
  — confirms the section is omitted when there's nothing to report.

## Out of Scope

- **MidEvent (live) matches** — not included in the heads-up; the Live tab covers these.
- **Knockout-stage spoiler leakage via standings** — if a recently-finished match was a
  knockout fixture, the `CURRENT STANDINGS` section (from `TournamentContextService`) already
  reflects the updated points, which can implicitly reveal the outcome. This is a pre-existing
  characteristic of the leaderboard inclusion and not introduced by this change; not addressed
  here.
- **WhatsApp digest reuse** — `UpcomingMatchesInsightService` is intended for reuse by a future
  WhatsApp digest job (per the original design spec). This change is compatible with that reuse
  since it's purely additive to the existing service interface.
