# Shot Feedback — Ball Animation + Keeper Telegraph

**Date:** 2026-05-28

## Problem

After tapping to shoot, the ball mark appears instantly at the target with no travel. The result (GOAL/SAVED/MISSED) only becomes clear when the overlay shows 300ms later. Saves feel arbitrary because the keeper dives to a random zone after the shot with no readable signal beforehand.

## Solution

Two complementary changes:

1. **Keeper telegraph** — keeper leans during the power bar phase, giving the player a visual cue to read (and potentially counter). Uses existing `lean-*` CSS classes and `bluffRate()` function, both already defined but never wired up.
2. **Ball travel animation** — ball slides from bottom-centre of the goal to its target position over 350ms, making the shot trajectory visible before the result appears.

---

## Keeper Telegraph

### When it happens
`_startPowerBar()` triggers the lean immediately when the power phase begins.

### Zone selection (moved earlier)
`_pickKeeperDiveZone()` is called in `_startPowerBar()` instead of `_resolveShot()`. This must happen before the telegraph so the actual dive zone is known.

### Telegraph vs bluff
After picking `actualDiveZone`, roll against `bluffRate(this.streak)`:
- **Not bluffing:** `telegraphZone = actualDiveZone`
- **Bluffing:** `telegraphZone` = random zone from `["left", "center", "right"]` filtered to exclude `actualDiveZone`

Apply `lean-{telegraphZone}` to the keeper element.

### On shot
`_resolveShot()` replaces `lean-{zone}` with `dive-{actualDiveZone}` as before. No change to save/goal resolution logic.

### Bluff rates (existing, unchanged)
| Streak | Bluff chance |
|--------|-------------|
| 0–4    | 0%          |
| 5–9    | 20%         |
| 10–14  | 40%         |
| 15–19  | 60%         |
| 20+    | 75%         |

Low streaks = honest keeper (easy to read). High streaks = keeper bluffs more often (harder).

---

## Ball Travel Animation

### CSS change
Add to `.game-ball-mark` in `game.css`:
```css
transition: left 0.35s ease-out, top 0.35s ease-out;
```

### JS change in `_placeBallMark()`
Instead of setting the final position and removing `hidden` in one step:
1. Set ball mark to start position: `left: 50%`, `top: 90%`
2. Remove `hidden` class
3. Force reflow: `void mark.offsetWidth`
4. Set final position (all existing left/top calculations unchanged)

The CSS transition animates the ball from start → final over 350ms.

### Result delay
Increase the `setTimeout` in `_resolveShot()` from `300ms` to `450ms` so the overlay appears after the ball lands.

---

## Files Changed

- `app/javascript/controllers/penalty_game_controller.js`
  - `_startPowerBar()` — call `_pickKeeperDiveZone()`, compute telegraph zone, apply `lean-{zone}` to keeper
  - `_resolveShot()` — remove `_pickKeeperDiveZone()` call (moved earlier); increase result delay to 450ms
  - `_placeBallMark()` — animate ball from start position to final position
  - `_startDirectionBar()` — reset keeper to default class (no lean) on new round
- `app/assets/tailwind/components/game.css`
  - Add `transition` to `.game-ball-mark`
