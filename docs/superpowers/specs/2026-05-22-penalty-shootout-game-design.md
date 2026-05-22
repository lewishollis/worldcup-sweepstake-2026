# Penalty Shootout Mini-Game — Design Spec

**Date:** 2026-05-22

## Overview

A browser-based penalty shootout mini-game embedded in the World Cup sweepstake app. Friends compete for the longest consecutive goal streak. Scores are persisted per friend and shown on a shared leaderboard.

---

## Data Model

New table: `game_scores`

| column | type | notes |
|---|---|---|
| `id` | bigint PK | |
| `friend_id` | bigint FK | references `friends` |
| `streak` | integer | goals scored before the miss that ended the session |
| `created_at` | datetime | when the streak ended |
| `updated_at` | datetime | |

- No changes to existing models or tables.
- All sessions are stored (one row per completed streak). The leaderboard displays only the **best streak per friend**.
- A score is only written when a streak ends via a keeper save. Navigating away or a timeout does **not** write a score — only genuine saves count (see Streak Reset Conditions).
- This table is named `game_scores` (not scoped to "penalties") so a second mini-game could reuse the pattern with a `game_type` column later. For now, all rows are implicitly penalty shootout.

### Leaderboard query

```sql
SELECT friend_id, MAX(streak) AS best_streak, MIN(created_at) AS first_achieved
FROM game_scores
GROUP BY friend_id
ORDER BY best_streak DESC, first_achieved ASC
```

Tie-breaker: earliest date the best streak was first achieved (rewarding whoever got there first).

---

## Routes & Controllers

```ruby
# config/routes.rb additions
get  '/game',        to: 'games#index'
post '/game/scores', to: 'games#create'
get  '/game/scores', to: 'games#scores'
```

| Method | Path | Action | Purpose |
|---|---|---|---|
| GET | `/game` | `GamesController#index` | Render game page |
| POST | `/game/scores` | `GamesController#create` | Save completed streak (JSON) |
| GET | `/game/scores` | `GamesController#scores` | Return leaderboard JSON |

`GamesController#index` loads all friends (for the picker) and the current leaderboard.

`GamesController#create` accepts `{ friend_id:, streak: }`, creates a `GameScore` record, and returns the updated leaderboard JSON in the same response (avoids a second fetch).

`GamesController#scores` returns the same leaderboard JSON format.

---

## View

**`app/views/games/index.html.erb`** — single page with three logical sections:

1. **Setup** — friend picker shown on first load or when no friend is selected in `sessionStorage`. Avatar grid of all friends; tapping one stores the choice and starts the game immediately.
2. **Game area** — goal graphic (with smoothed live cursor tracking), direction bar, power bar, streak counter, personal best, friend name, result overlay with "Play Again" button.
3. **Leaderboard** — always visible below the game area. Best streak per friend, sorted descending. Top 3 highlighted gold/silver/bronze. Each row shows friend name, best streak, and a small "last played" timestamp for social context. New personal best rows animate briefly on update.

---

## Stimulus Controller

**`app/javascript/controllers/penalty_game_controller.js`**

### State machine

Two top-level states:

- **`setup`** — friend picker visible. Entered on page load if no friend in `sessionStorage`, or if player explicitly wants to switch identity.
- **`playing`** — friend confirmed; sub-states handle the shot cycle:

```
playing:aim_direction → playing:aim_power → playing:result → playing:aim_direction (on goal)
                                                            ↘ setup (on save — score posted)
```

### Sub-states during `playing`

| Sub-state | Description |
|---|---|
| `aim_direction` | Direction bar sweeping. Live cursor tracks position in goal graphic (smoothed, see below). |
| `aim_power` | Direction locked. Power bar sweeping. Keeper telegraph shown. |
| `result` | "GOAL ⚽" or "SAVED 🧤" overlay shown for ~1.5s. "Play Again" button visible immediately. |

Friend name and personal best are shown persistently during all `playing` sub-states.

### Game mechanic

**Direction bar:** sweeps left↔right continuously at a fixed speed. Player taps to freeze. Maps to three zones: `left` (0–33%), `center` (34–66%), `right` (67–100%).

Corner zones (`left` and `right`) are tactically valuable — the keeper is less likely to reach them — but the bar moves faster through corners, making them harder to time precisely.

**Live cursor tracking:** a visual indicator moves inside the goal graphic in sync with the direction bar position. This is smoothed (interpolated, not snapped) so it doesn't feel twitchy and doesn't inadvertently give the player more precision than the zone system provides. The cursor reflects zone position only — left third, center third, right third.

**Keeper telegraph:** immediately after the player locks direction, the keeper graphic leans left, center, or right (~0.5s CSS animation). The player sees this telegraph **before** the power bar starts, giving them a moment to factor it in.

**Telegraphed direction vs actual dive direction:**

These are explicitly separate values computed by the controller:

- `telegraphed_direction` — what the keeper shows (always set before power bar starts)
- `actual_dive_direction` — what the keeper actually does (computed when shot is fired, based on bluff rate)

At low streaks: `actual_dive_direction === telegraphed_direction` (no bluff).
At higher streaks: `actual_dive_direction` may differ from `telegraphed_direction` (bluff).

The player only ever sees `telegraphed_direction`. The outcome is determined by `actual_dive_direction`.

**Power bar:** sweeps low↔high after direction is locked. Player taps to freeze. Maps to: `low`, `mid`, `high`.

**Outcome logic:**

| Shot direction vs **actual** dive direction | Power | Result | Rationale |
|---|---|---|---|
| Different | any | GOAL | Keeper dived the wrong way |
| Same | `low` or `mid` | SAVED | Keeper had time to reach it |
| Same | `high` | GOAL | **Power beats keeper timing** — shot too fast to stop even on correct dive |

The "power beats keeper timing" rule is intentional: it gives the player a meaningful use for high power, and rewards committing to a direction the keeper guesses correctly but being fast enough to beat them anyway.

**Difficulty scaling (streak-based):**

| Streak | Keeper bluff rate | Notes |
|---|---|---|
| 0–4 | 0% | Keeper always dives where telegraphed — read the lean, go elsewhere |
| 5–9 | 20% | Occasionally bluffs — lean is mostly trustworthy |
| 10–14 | 40% | Bluffs nearly half the time — harder to read |
| 15–19 | 60% | Telegraph is unreliable |
| 20+ | 75% | Telegraph is mostly noise — skill must carry you |

### Streak reset conditions

| Event | Streak resets? | Score written? |
|---|---|---|
| Keeper save | Yes | Yes — POSTed to `/game/scores` |
| Player navigates away | No reset (session preserved) | No |
| Browser tab closed | No reset (sessionStorage lost but no partial save) | No |
| Timeout / idle (no tap within 30s on a bar) | Yes — treated as a miss | No — timeouts don't write scores |
| Player taps "Switch player" | Yes | No |

Only keeper saves produce a written score. This keeps the leaderboard clean and honest.

### UX details

- Friend name shown prominently above the goal during play.
- Personal best shown alongside the live streak counter (e.g. "Streak: 7 | PB: 12 🔥").
- "Play Again" button appears immediately in the result overlay — player doesn't need to wait for the 1.5s animation to finish to restart.
- Leaderboard row animates (brief highlight flash) when the current player sets a new personal best.
- Leaderboard shows a small "last played" relative timestamp per friend (e.g. "2h ago") for social context.

---

## Navigation

- New tab added to `app/views/layouts/_bottom_nav.html.erb` with a ⚽ icon and label "Game".
- Route: `/game`

---

## Out of Scope

- No authentication — friend identity is self-reported via the picker.
- No daily limits or cooldowns.
- No sound effects (can be added later).
- No multi-game `game_type` column for now — schema is ready for it but not implemented.
