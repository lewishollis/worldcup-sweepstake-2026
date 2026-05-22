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
- All sessions are stored. The leaderboard displays only the **best streak per friend** (max streak grouped by friend_id).
- A score is only written when a streak ends (i.e. the keeper saves the ball).

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

`GamesController#index` loads all friends (for the picker) and the current leaderboard (best streak per friend, ordered descending).

`GamesController#create` accepts `{ friend_id:, streak: }`, creates a `GameScore` record, and returns the updated leaderboard JSON.

`GamesController#scores` returns the same leaderboard JSON (used to refresh after a new score).

---

## View

**`app/views/games/index.html.erb`** — single page with three logical sections:

1. **Friend picker** — shown on first load. Avatar grid of all friends. Selecting one stores the choice in `sessionStorage` and transitions to the game.
2. **Game area** — goal graphic (with live cursor tracking), direction bar, power bar, streak counter, result overlay.
3. **Leaderboard** — always visible below the game area. Shows each friend's personal best streak, sorted descending, with gold/silver/bronze highlights for top 3.

---

## Stimulus Controller

**`app/javascript/controllers/penalty_game_controller.js`**

### State machine

```
idle → picking_friend → aim_direction → aim_power → result → aim_direction (loop)
                                                           ↘ idle (on miss — score posted)
```

### States

| State | Description |
|---|---|
| `idle` | Friend picker visible |
| `picking_friend` | Friend selected, "Play as [name]" shown with Play button |
| `aim_direction` | Direction bar sweeping. Cursor tracks position live in goal graphic. |
| `aim_power` | Power bar sweeping. Direction frozen, keeper lean shown. |
| `result` | "GOAL ⚽" or "SAVED 🧤" overlay shown for ~1.5s |

### Game mechanic

**Direction bar:** sweeps left↔right continuously. Player taps to freeze. Maps to three zones: `left` (0–33%), `center` (34–66%), `right` (67–100%). Corner zones (`left` and `right`) have a narrower sweet spot — the bar spends less time there — making them harder to time but tactically valuable.

**Keeper telegraph:** immediately after direction is locked, the keeper graphic briefly leans left, center, or right (CSS animation, ~0.5s). This is the keeper's **intended** dive direction, but it may be a bluff (see difficulty scaling).

**Power bar:** sweeps low↔high. Player taps to freeze. Maps to: `low`, `mid`, `high`.

**Outcome logic:**

| Shot direction vs keeper dive | Power | Result |
|---|---|---|
| Different | any | GOAL |
| Same | `low` or `mid` | SAVED |
| Same | `high` | GOAL (too fast) |

**Difficulty scaling (streak-based):**

| Streak | Keeper bluff rate | Notes |
|---|---|---|
| 0–4 | 0% | Keeper always dives where telegraphed |
| 5–9 | 20% | Occasionally bluffs |
| 10–14 | 40% | Bluffs nearly half the time |
| 15–19 | 60% | Hard to read |
| 20+ | 75% | Very hard — telegraph is mostly noise |

A "bluff" means the keeper dives to a **different** zone than telegraphed. The player must decide whether to trust or ignore the lean.

### Scoring

- Streak increments by 1 for every goal.
- On a save: current streak is POSTed to `/game/scores` via `fetch`. Leaderboard updates. Game resets to `idle`.
- Friend identity stored in `sessionStorage` — navigating away and returning within the same browser session skips the friend picker.

---

## Navigation

- New tab added to `app/views/layouts/_bottom_nav.html.erb` with a ⚽ icon and label "Game".
- Route: `/game`

---

## Out of Scope

- No authentication — friend identity is self-reported via the picker.
- No daily limits or cooldowns.
- No sound effects (can be added later).
- No animations beyond keeper lean and result overlay.
