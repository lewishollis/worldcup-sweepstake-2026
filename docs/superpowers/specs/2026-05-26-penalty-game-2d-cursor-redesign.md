# Penalty Game — 2D Crosshair Cursor Redesign

**Date:** 2026-05-26
**Status:** Approved

## Problem

The penalty game has two clarity issues:

1. **The yellow cursor only moves left/right** — players cannot see where the ball will land vertically. Height is invisible until after the shot.
2. **The power bar label "POWER ↑" is confusing** — it's a horizontal left-to-right bar, but "↑" implies vertical. Players don't understand that high power = ball over the crossbar.

## Solution: 2D Crosshair Cursor

The cursor on the goal gains a vertical dimension. Phase 1 sweeps it left/right as before. Phase 2 sweeps it up/down, so the crosshair always shows the exact landing spot in the goal. If power goes too high, the cursor visibly escapes above the crossbar — making the "over the bar" miss obvious before it's announced.

No change to game logic, save conditions, or keeper AI.

---

## Phase 1 — Aim (Direction)

**Unchanged from current behaviour.** The cursor sweeps left/right driven by `dirPct`.

- `cursorTarget.style.left` maps `dirPct` → 5–95% of goal width (existing formula)
- `cursorTarget.style.top` is fixed at `85%` (cursor center near the ground) during this phase
- Bar label changes: `"DIRECTION ← →"` → `"AIM ←→"`
- Hint text: `"Tap the ball to aim"` — no change

---

## Phase 2 — Power / Height

**New: cursor also moves vertically**, driven by `pwrPct`.

### Cursor vertical mapping

`cursorTarget.style.top` is updated every animation frame during the power sweep:

| `pwrPct` | `top` (cursor center) | Visual position        |
|----------|-----------------------|------------------------|
| 0        | 85%                   | Near ground            |
| 92       | 0%                    | At the crossbar        |
| 100      | −20%                  | Above the crossbar     |

**Formula (piecewise):**
- For `pwrPct` 0–92: `top = 85 - (pwrPct / 92) * 85`  → maps 0→85%, 92→0%
- For `pwrPct` 92–100: `top = 0 - ((pwrPct - 92) / 8) * 20` → maps 92→0%, 100→−20%

The cursor's `transform: translate(-50%, -50%)` is unchanged — `top` refers to the cursor's center point.

### Goal post overflow

The `.game-goal-post` element (and its parent) must not clip content above the top border. The cursor escaping upward must be visible. Remove or override any `overflow: hidden` on the goal container. The green pitch background wrapping the goal can remain.

### Bar label change

`"POWER ↑"` → `"POWER ↕"`

Hint text changes: `"Tap the ball to shoot!"` → `"Tap to shoot — stop it before it flies over the bar!"`

### Miss condition (logic unchanged)

`isMissPower(pct)` still triggers at `pct > 92` (constant `POWER_MISS_EDGE = 92`). No logic change — only the visual now makes the miss legible.

---

## How-to-Play Modal Copy

Replace the two step descriptions:

| Step | Current | New |
|------|---------|-----|
| 1 | "Tap the ball to lock the direction bar" | "Tap to aim — stop the crosshair left, centre, or right." |
| 2 | "Tap again to lock your power" | "Tap to shoot — stop it before it flies over the bar." |
| 3 | "Score streaks 🔥 Avoid the red zones — that's a miss" | unchanged |

Step titles ("Aim", "Shoot", "Score streaks 🔥") are unchanged.

---

## Files to Change

| File | Change |
|------|--------|
| `app/javascript/controllers/penalty_game_controller.js` | Update `_updateDirectionUI` to set cursor top to 85%; update power sweep to also set cursor top using piecewise formula; update label/hint strings |
| `app/views/games/index.html.erb` | Update bar label from `"POWER ↑"` to `"POWER ↕"`; update hint default text |
| `app/assets/tailwind/components/game.css` | Remove `top: 50%` from `.game-cursor` (it becomes fully JS-controlled); ensure goal wrapper does not clip overflow above crossbar |

---

## What Does NOT Change

- `POWER_MISS_EDGE = 92` constant
- `DIRECTION_MISS_EDGE = 8` constant
- `DIRECTION_SPEED`, `POWER_SPEED` constants
- Keeper dive logic
- Shot resolution (`_resolveShot`, `_placeBallMark`)
- Leaderboard, streaks, save/miss/goal result display
- Two-tap mechanic
