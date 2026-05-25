# Penalty Game — "How to Play" Modal

## Summary

A one-time instructional modal shown to first-time visitors of `/game`. Dismissed with a single button tap and never shown again (persisted via `localStorage`).

## Behaviour

- Renders on top of the game page as a full-screen dark overlay with blur
- Appears immediately on `connect()` in the Stimulus controller, before the user interacts with anything
- Dismissed by tapping "Got it, let's play!" — no other close mechanism (no tap-outside, no X button), to ensure users read it
- After dismissal, `localStorage.setItem("penalty_how_to_play_seen", "1")` is written
- On subsequent visits, if the key exists, the modal is skipped entirely

## Content

Three numbered steps:

1. **Aim** — Tap the ball to lock the direction bar
2. **Shoot** — Tap again to lock your power
3. **Score streaks 🔥** — Avoid the red zones — that's a miss

## Implementation

All logic lives in `penalty_game_controller.js` — no new files, no server changes.

- On `connect()`, check `localStorage.getItem("penalty_how_to_play_seen")`
- If absent, call `_showHowToPlayModal()` which imperatively builds and appends the overlay to `document.body`
- The "Got it" button sets the localStorage key and removes the overlay
- The overlay is built in JS (same pattern as the existing `_showPlayerConfirmPopup`)

## Visual Design

- Full-screen overlay: `position:fixed; inset:0; background:rgba(0,0,0,0.65); backdrop-filter:blur(3px)`
- Card: dark `#1a1a2e` background, `2px solid #4a9d6f` border, `border-radius:16px`
- Steps rendered as a column of rows, each with a green numbered circle, bold title, and grey subtitle
- "Got it, let's play!" button: full-width, green (`#4a9d6f`), matches existing game button style
