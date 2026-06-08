# Professional Penalty Game — Design Spec

**Date:** 2026-06-08

## Problem

The game works but doesn't feel professional. The two-tap mechanic is not obviously connected to where the ball will land — players don't immediately understand that stopping the direction bar determines left/right and stopping the power bar determines height. The result screen is instant and flat. There's no celebration on goal and no tactile feedback.

## Goal

Make the penalty game feel like a polished mobile mini-game through four independent, layered improvements — all visual/JS only, no audio assets required, no game rule changes.

---

## Layer 1 — Live Shot Preview (Intuition)

**Problem:** Players don't see the connection between the sweeping bars and the shot destination until after they've fired.

**Solution:** A ghost ball (semi-transparent ring) on the goal surface shows the predicted landing position in real time as both bars sweep.

### Behaviour

- **Aim phase:** Ghost ball sits at ground level (`top: 85%`) and slides left/right in sync with the cursor — same `goalPct` calculation already used for the cursor. The live cursor (yellow dot) and ghost ring are both visible simultaneously.
- **Power phase:** Ghost ball stays at the locked horizontal position and rises vertically in sync with `_updateHeightUI` — same `topPct` formula. When power enters the miss zone (>92%), ghost ball exits above the crossbar to preview the over-bar miss.
- **On shot:** Ghost ball hides the moment the ball mark is revealed (`_resolveShot`).
- **On reset:** Ghost ball returns to ground-level position at the start of each direction phase.

### Visual design

- Ghost ball is a 22×22px semi-transparent yellow ring (`rgba(255,255,0,0.15)` fill, `rgba(255,255,0,0.5)` dashed border).
- A short dotted vertical line connects the cursor dot to the ghost ring during the power phase, making the "cursor → landing" relationship explicit.
- Red-tinted overlay strips on the left 8% and right 8% of the goal surface (matching `DIRECTION_MISS_EDGE`) show the wide-miss zones visually on the goal — not just on the direction bar.

### Implementation

- Add `ghostBall` target to controller targets, rendered as an absolutely positioned `<div>` inside `.game-goal-post` in the ERB template.
- `_updateDirectionUI` sets `ghostBall.style.left = ${goalPct}%` and `ghostBall.style.top = 85%`.
- `_updateHeightUI` sets `ghostBall.style.top = ${topPct}%` (same value as cursor).
- `_startDirectionBar` resets and shows ghost ball; `_resolveShot` hides it.
- Red miss-zone strips are static `<div>` elements with pointer-events none, rendered once in the ERB template.

---

## Layer 2 — Tap Feedback + Keeper Drama (Feel)

### Haptics

`navigator.vibrate()` called at key moments (silently no-ops on unsupported browsers):
- Short pulse (30ms) on every tap of the ball button.
- Double pulse (50ms + 50ms gap + 50ms) on GOAL.
- Long buzz (150ms) on MISS or SAVED.
- No vibration on timeout.

### Direction-lock flash

When aim is locked (`lockDirection`), the direction bar wrapper briefly adds a CSS class `locked-flash` that triggers a 200ms green highlight animation, giving clear confirmation the aim was registered.

### Power bar entrance

When the power bar appears (`_startPowerBar`), it plays a 150ms `pop` scale animation (`transform: scaleY(0) → scaleY(1)`) to make the phase transition feel deliberate rather than instant.

### Keeper dive snap

The keeper `dive-*` transition is tightened from `0.35s` to `0.2s` with a sharper cubic-bezier (`cubic-bezier(0.22, 1, 0.36, 1)` → `cubic-bezier(0.34, 1.56, 0.64, 1)`), making the dive feel like a committed lunge rather than a smooth slide.

---

## Layer 3 — Goal + Miss Reactions (Celebration)

### Screen flash

A full-screen overlay div (z-index 9998, pointer-events none) briefly flashes on result:
- GOAL: white flash, 150ms, opacity 0.4 → 0.
- MISS: red flash, 120ms, opacity 0.3 → 0.
- SAVED: dark blue flash, 120ms, opacity 0.25 → 0.

### Net ripple

When the ball mark lands inside the goal (not a miss), a ripple `<div>` (absolutely positioned inside `.game-goal-post`, pointer-events none) is placed at the ball mark's landing position and plays a CSS `@keyframes` radial-expand animation: starts as a small circle (10px), expands to 60px with opacity fading from 0.6 to 0. Duration: 400ms. The div is reused each round — JS sets its `left`/`top` to match the ball mark position and re-triggers the animation via a reflow before adding the active class.

### Result overlay slide-up

The result overlay (`game-result-overlay`) animates in from `translateY(20px), opacity 0` to `translateY(0), opacity 1` over 200ms instead of appearing instantly.

### Streak milestones

In `_showResult("goal")`, the hint text below the goal responds to streak level:
- Streak 1–2: `"Next up…"`
- Streak 3–4: `"3 in a row! 🔥"`
- Streak 5–9: `"On fire! 🔥🔥"` — hint text itself pulses (CSS animation).
- Streak 10+: `"Unstoppable! 🔥🔥🔥"` — hint text pulses, result text gets larger class `milestone`.

---

## Layer 4 — Visual Presentation (Polish)

### New PB animation

`_flashNewPb()` already adds `new-pb` class with a reflow restart. Enhance the CSS animation to slide the row in from the right and flash gold for 1 second, rather than just a simple highlight.

### Aim zone labels

During the aim phase only, three subtle labels appear inside the goal: "LEFT", "CENTRE", "RIGHT" in the corresponding thirds. They fade in 200ms after the direction bar starts and fade out when aim is locked. Implemented as static `<span>` elements inside the goal, shown/hidden via class toggle.

### Power level label

At the moment of shot fire (`_resolveShot`), a small label (`HIGH`, `MID`, `LOW`) fades in just below the ball mark. It is hidden when the result overlay appears (450ms later), giving the player a brief read on their power execution before the outcome is shown. Implemented as a single `<div>` target inside the goal, positioned to match the ball mark's horizontal position.

### Miss-zone strip on goal

Already described in Layer 1 — red-tinted left/right strips matching `DIRECTION_MISS_EDGE` = 8%.

---

## Files Changed

| File | Changes |
|---|---|
| `app/javascript/controllers/penalty_game_controller.js` | Ghost ball sync in `_updateDirectionUI` + `_updateHeightUI`; haptics; lock flash; power bar pop; screen flash; streak milestone text; power level label |
| `app/assets/tailwind/components/game.css` | Ghost ball styles; direction lock flash; power bar pop; screen flash overlay; net ripple; result slide-up; streak milestone pulse; new PB animation; zone labels; keeper dive snap |
| `app/views/games/index.html.erb` | Add ghost ball `<div>`, miss-zone strip `<div>`s, screen flash overlay `<div>`, aim zone label `<span>`s |

---

## Constraints

- No audio assets or Web Audio API.
- No game rule changes — scoring, miss thresholds, keeper bluff rates, streak logic all unchanged.
- No new backend endpoints.
- All four layers are independent and can ship in order.
